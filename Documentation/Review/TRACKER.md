# Review tracker — live worklist

## ▶▶ START HERE (written 2026-10-25, after WS-17)

The full sequenced list with file ownership and effort is §4 of
`findings/WS-17-triage.md`. This is just the front of that queue, with what has since been
done struck off, so a session can begin without re-deriving anything.

> ✅ **Verified 2026-10-26 on the owner's Mac, at PR #51's head.** The 2026-10-25 agent run
> (W-A, W-B, W-E, W-J) was done in a Linux container with no Xcode and no SwiftLint, so it
> compiled nothing and executed no test. Those commands have now been run:
>
> | Command | Result |
> |---|---|
> | `generic/platform=iOS` device build — the only one that compiles MLX | ✅ **BUILD SUCCEEDED**, 0 errors: W-E's wiring typechecks |
> | `Fast` plan, iPhone 17 Pro / OS 26.5 | ✅ **368 tests, 0 failures** — after the fix below |
> | `swiftlint lint` from `HealthApp/` | ✅ **exactly 5**, the baseline, none in the changed lines |
>
> ⚠️ **It did not build as pushed.** `DatabaseTests.swift:663` put an `async` call inside an
> `XCTAssertNotNil` autoclosure — a hard compile error — so the test bundle failed to build
> and **every test W-B and W-J added had never run, in either plan**. Fixed 2026-10-26 by
> hoisting the call to a `let`. The lesson stands as the banner first wrote it: a run that
> cannot compile cannot report a test as passing, and the negative check it skipped is
> exactly what would have caught this.

### ▶ CI is green (2026-10-26, PR #52). Its first run, on PR #51, found its own bug

`.github/workflows/ci.yml` executed for the first time. It diagnosed itself exactly as its
header comment intended, so **W-I's "the workflow has never executed" is now answered**:

That first run, on PR #51:

| Job | Result |
|---|---|
| Report the runner's toolchain | ✅ — and it is the job that found the bug |
| SwiftLint (baseline 5) | ✅ **green against the baseline**, on `macos-15` with `brew install swiftlint` |
| Tests | ❌ build failed before any app source compiled |
| Device build | ❌ same, in a different dependency target |

**The bug is the missing toolchain selection, not the diff.** `macos-15` defaults to **Xcode
16.4 (16F6)**, whose iOS 18.5 SDK cannot build an `IPHONEOS_DEPLOYMENT_TARGET` of 26.0 — the
run warns exactly that — and `mlx-swift-lm` then fails Swift 6 concurrency checks under it
(`MLXVLM/MediaProcessing.swift:16`, `private let context = CIContext()`, `CIContext` not
`Sendable`). No job runs `xcode-select`, so all three build jobs inherit 16.4. Both failures
are in checked-out SwiftPM dependencies; **no `HealthApp/` file was compiled in either job**,
so the suite and the device typecheck both remain unrun.

What the runner actually has, measured rather than assumed:

- **Xcode**: 16.0–16.4 and **26.0.1, 26.1.1, 26.2.0, 26.3.0** installed; **16.4 is the image
  default**, which is the bug, and `ci.yml` now pins 26.2.0 over it.
- **iOS runtimes**: 18.5, 18.6, **26.0, 26.1, 26.2** — note **no 26.5**, which this file and
  `CLAUDE.md` both name in their local commands. A destination pinned to `OS=26.5` fails here.
  `ci.yml`'s `SIMULATOR` pins no OS, so it is fine as written.
- **Simulators**: iPhone 17 Pro, 17 Pro Max, Air, 17 all present. The names in `CLAUDE.md`
  are right; only the OS pin is wrong.

**Fixed in PR #52.** One workflow-level
`DEVELOPER_DIR: /Applications/Xcode_26.2.0.app/Contents/Developer`, rather than a
`sudo xcode-select` step repeated in each build job: it pins one Xcode for every job and
every step, needs no sudo, and cannot be half-applied by someone who adds a job later. The
header of `ci.yml` says why it must not be removed, and the `environment` job now prints both
the pinned Xcode and the image's default, so this failure stays legible in the next red run.

**26.2.0, not the 26.1.1 this file first guessed.** Of the four 26.x on the image it is the
newest whose matching simulator runtime is actually installed (26.0, 26.1, 26.2, no 26.3),
and a newer compiler is what the `CIContext` diagnostic needs — that dependency compiles
clean under the Xcode 27.x used locally. The runner resolves the path to `Xcode_26.2.app`,
reporting **Xcode 26.2 / 17C52** against the image default of **16.4 / 16F6**.

Run `40256518153`, all four jobs green:

| Job | Result | Wall time |
|---|---|---|
| Report the runner's toolchain | ✅ prints 26.2 pinned and 16.4 default | 1m11s |
| SwiftLint (baseline 5) | ✅ | 12s |
| Tests (`Fast`, on a pull request) | ✅ **total 368 passed 368 failed 0**, read from the `.xcresult` | ~22m |
| Device build | ✅ **the first time anything in `MLXOnDeviceLLM/` has compiled in CI** | 10m56s |

Two things that run settles, both worth knowing before trusting a green tick:

- **A full run costs 15–25 minutes**, plus ~4½ minutes queueing for a hosted macOS runner.
  Nearly all of it is compiling ~30 SwiftPM packages from scratch: the `actions/cache` step
  caches the *checkouts*, not the build products, and the device-build job has no cache step
  at all. The same suite is 32 seconds of test time locally against warm DerivedData.
- **`PreRelease` has still never run on CI.** The plan is chosen by event — `Fast` on a pull
  request, `PreRelease` on a push to `main` — so the two UI tests reach CI for the first time
  when #52 merges. A hosted runner is where UI tests are most likely to misbehave, and a red
  run there is the workflow's problem rather than the code's.

### Beta-blockers — what stands between you and a tester build

| | Item | State |
|---|---|---|
| W-A | Icon alpha, `aps-environment`, delete unused icon set | **done 2026-10-25.** `AppIcon-Doctor-Dark.appiconset` deleted (16 files; still 0 references in `project.pbxproj`, and the asset catalog's root `Contents.json` lists no children, so nothing was orphaned). `BisonHealthAI_ProIcon_1024.imageset` was left alone — `ContentView.swift:261` uses it. |
| W-B | Show why a document failed | **done 2026-10-25.** ⚠️ **W-B took schema v15** — W-Q was not in flight, so the collision resolved in W-B's favour. **W-Q is now v16.** `documents.failure_reason` holds the reason, written in the same statement as the status and cleared by any status other than `.failed`. Stored **encrypted** (`encryptTextField`), not filename-free as WS-17 suggested: two of these error strings interpolate the file name, and encrypting the column is cheaper to keep correct than auditing every present and future error case for PHI. Not an `UnreadableField` — a corrupt message is not worth refusing to save a document over. ⚠️ **New finding, not fixed:** the documents table has **two** `buildMedicalDocument` readers (`+Documents.swift` and `+MedicalDocuments.swift`) and **three** full-row writers, all with hand-maintained column lists. Codex caught v15 being wired into only one of each — the UI reads through the *other* one, so the first cut of W-B did nothing after a relaunch. All five sites now carry the column, but the next column added will hit the same trap. |
| W-C | One device archive + three owner-only checks | **done 2026-10-25 by the owner** (archive built; background mid-reply, one Bedrock call, keychain restore on a real upgrade all run). ⚠️ **The outcomes were not reported to this session** — see "What W-C settled" below. |
| W-D | TestFlight tester notes | **done 2026-10-25 by the owner.** |

### What W-C settled — and what is still unknown

The device session happened, so three things that could only be checked on hardware have now
been checked. **This session was not told the results**, so they are recorded as pending an
answer rather than as passes:

| Check | What it decides | Status |
|---|---|---|
| Background mid-reply | **W-E.** WS-17 would not promote WS-11-02 + WS-03-03 without a device: `isSuspendedForBackground` is read only to make suspend/resume idempotent, and the unload queues behind the running generation. If this crashed or hung, W-E is a confirmed P1; if it was clean, W-E drops down the list. | awaiting the owner's result |
| One real Bedrock call | **Item 17 / decision 5.** The model id was corrected from a dotted `claude-sonnet-4.5-…` to `claude-sonnet-4-5-20250929-v1:0`. If Bedrock answered, that fix is confirmed and Bedrock stays in scope. | awaiting the owner's result |
| Keychain restore on a real upgrade | **Item 8 / decision 3.** The database key became a synchronizable Keychain item so a restore can read its own data. A device-only key still opening its database after the change was the one thing never verified. | awaiting the owner's result |

Two decisions were also meant to be settled during this run: **measure the 384 KiB/token KV
constant** (it is still an estimate, and `MLXMemoryBudget`'s floor exists only because of
that), and **re-verify item 32**, the Import-tap mitigation.

**Everything else is optional for a beta.** WS-17 verified that both P0s, the
restore-data-loss bug, PHI-at-rest, the exfiltration chain, fail-closed consent and the
privacy copy are genuinely fixed, at the specific sites rather than from this file.

### Best next engineering work, in order

1. ~~**W-F**~~ — **done 2026-10-25.** The title write is now title-only at both layers
   (`DatabaseManager.updateConversationTitle(id:title:)`), so a generated title can no longer
   revert `includedHealthDataTypes` / `includedPersonalInfoCategories` — the user's choice
   about what health data a conversation may share — or drop a message sent during the
   seconds-long model call. And `loadConversations` merges instead of replacing, so
   `ChatView.task` firing on every appearance can no longer orphan a streaming placeholder
   into the "conversation cleared mid-stream" guard. Stored state stays authoritative for
   everything it owns; the in-memory copy contributes only messages the database has not seen.
   **W-G and W-S are unblocked** (they share these files).
2. ~~**W-G**~~ — **done 2026-10-25.** Both review sheets, their observers and
   `restorePendingImportReviews()` now live on `ContentView`, so a restored review surfaces
   wherever the user is instead of waiting for them to open Documents. Found while moving it:
   `DocumentDetailView` held a **second** presenter of the same sheet and an 83-line duplicate
   of the completion handler — with the root presenting too, that would have been two sheets
   racing for one review. Both removed; `completeImportReview` now lives on
   `DocumentProcessor` beside `completeGeneticTestReview`, uses the processor's injected
   `healthDataManager` rather than the singleton, and the completion path awaits the stored
   row's deletion so a completed review cannot be re-offered next launch. **W-H is unblocked.**
3. ~~**W-H**~~ — **done 2026-10-25.** The grid is one `.adaptive` column instead of a
   hardcoded four, and the tile fills its column instead of asserting a fixed 200 pt. The old
   arithmetic really did overflow: 834 pt portrait gives a 188 pt column, and a Split View
   half-pane gives ~80 pt. The dead iPad master-detail is **deleted**, not revived —
   `embedInNavigation` was always false because `HealthTabView` is the only caller and
   deliberately owns one nav bar, so `documentsSplitView`, `documentsStackView` and
   `HealthDataView`'s own stack branch were all unreachable. **Whether iPad should get a real
   two-column layout is a design question about `HealthTabView`** and is a decision for the
   owner, not a flag to flip (see below).
4. ~~**W-E**~~ — **done 2026-10-25.** `isSuspendedForBackground` is now genuinely consulted:
   the streaming token loop evaluates `MLXTurnInterruption` at every chunk and breaks at a
   token boundary, so `suspendForBackground()`'s `acquire()` waits one token instead of up to
   the full 4,096-token budget. The gate is still taken rather than skipped — tearing down
   with GPU work in flight is what the gate exists to prevent, so the fix is to make the
   generation stop, not to stop waiting for it. `MLXGPUGate` is unchanged, so no
   `acquire()` call site had its control flow altered. A kept partial reply gets a notice and
   `finishReason: "interrupted"`; one too short to be an answer throws
   `MLXOnDeviceError.generationInterrupted`, which drops the empty assistant placeholder and
   leaves the user's message retryable (existing handling in `AIChatManager`). The decision
   rule is a plain value type with unit tests. **The wiring typechecks** as of 2026-10-26 —
   the `generic/platform=iOS` build succeeds — but it still *executes* in no test, because
   the simulator stubs the generate body out. Severity stays unconfirmed: the owner's
   background-mid-reply result was never reported back.
   ⚠️ **New finding, not fixed (2026-10-26): W-E covers one of the generation paths, not
   all of them.** Only `sendStreamingChatMessage` evaluates `MLXTurnInterruption`.
   `sendMessage` → `collectResponse` still takes `MLXGPUGate` and holds it for a whole
   `maxTokens` generation with no boundary check — the original bug's exact shape — and its
   callers are `AppointmentPrepManager` (three consecutive calls), `AIChatManager`'s
   non-streaming fallback and its title generation, `BloodTestMappingService` and
   `MedicalDocumentExtractor`. The run flagged only `extractFromDocument` as deliberately
   out of scope, so this one reads as an oversight rather than a decision. **Promoted to
   W-T below.** Smaller, same area: `MLXOnDeviceError.generationInterrupted` is thrown for both
   reasons but its text is background-only, so a turn the user cancelled inside the first 40
   characters gets "because the app went to the background" in a visible error alert.
5. ~~**W-I**~~ — **mostly done 2026-10-25.** Two shared test plans in
   `HealthApp/TestPlans/` (**PreRelease** = unit + UI + coverage, the scheme's default so a
   bare `xcodebuild test` still runs everything; **Fast** = unit only, for pull requests),
   `.github/workflows/ci.yml` with lint/test/device-build jobs, and `ExportOptions.plist`.
   Verified locally: both plans resolve and run the right counts (346 vs 348 on 2026-10-25;
   `Fast` is 368 as of 2026-10-26), the lint gate catches a sixth violation, and the bare
   invocation still covers everything.
   **Left for the owner: the Apple Distribution identity** — without it no signed export can
   be produced, so `ExportOptions.plist`'s `method` is unvalidated. **The workflow now runs
   green**: its first run diagnosed its own missing toolchain selection, fixed in PR #52 by
   pinning Xcode 26.2.0 through `DEVELOPER_DIR` (368/368 tests, and MLX compiling in CI for
   the first time) — see the CI section at the top of this file. `PreRelease`, and so the UI
   tests, still reach CI for the first time only when a merge pushes to `main`.
   **W-R is unblocked.**
6. ~~**W-J**~~ — **done 2026-10-25**, so **W-K is unblocked** (it owns the same file; do not
   run them together). A v10 fixture now exists, built the established way — let
   `DatabaseManager` create the real schema, then wind it back, including the hard part: the
   v11 columns written back as genuine plaintext, which the app's API will never produce.
   It asserts the v11 step *ran* (the stored bytes are no longer the readable strings) **and**
   that the app reads the originals back; asserting only the second half would pass against
   plaintext. Also covered: the whole chain reaching `currentDatabaseVersion` (asserted
   against the constant, never a literal), every later step's schema change, migration-backup
   deletion after a committed migration, and `resetDatabase()` sweeping a leftover backup.
   ⚠️ **New finding, not fixed here (tests only):** `encryptDocumentPHIColumns` and
   `encryptChatTitles` are **not idempotent** — unlike the v14 tags helper they re-encrypt
   unconditionally, so a second pass over an already-migrated row double-encrypts and
   strands the data for good. Not reachable in production, because each step and its version
   bump share one transaction, so v11 only runs at stored version 10. Making it idempotent is
   a `DatabaseManager` change: **promoted to W-U below.** No v11 idempotency test was written,
   because the honest one would assert data loss.
7. **W-T** — **finish W-E: the other generation paths.** Found 2026-10-26 while verifying
   PR #51. Only `sendStreamingChatMessage` evaluates `MLXTurnInterruption`; `sendMessage` →
   `collectResponse` still takes `MLXGPUGate` and holds it for a whole `maxTokens`
   generation with no boundary check, so a background trip there queues the unload behind
   the full budget — the exact bug W-E set out to fix, in the path `AppointmentPrepManager`
   (three consecutive calls), `AIChatManager`'s non-streaming fallback and its title
   generation, `BloodTestMappingService` and `MedicalDocumentExtractor` all use. W-E's own
   `extractFromDocument` exclusion stays deliberate: stopping mid-document would return a
   partial extraction that looks complete. Owns `MLXOnDeviceClient.swift`, so it serialises
   against anything else touching that file, and only a `generic/platform=iOS` build
   typechecks it. While there: `MLXOnDeviceError.generationInterrupted` is thrown for both
   interruption reasons but its text is background-only, so a turn cancelled inside the
   first 40 characters tells the user the app went to the background.
8. **W-N** — the ~25 `foregroundColor(BisonTheme.gold)` sites at 2.7:1. Item 40 fixed
   white-on-gold only; this is the other half and I had wrongly treated it as done.
9. **W-U** — **make the v11 encryption helpers idempotent.** `encryptDocumentPHIColumns` and
   `encryptChatTitles` re-encrypt unconditionally, unlike the v14 tags helper, so a second
   pass double-encrypts and strands the data for good. **Not reachable today** — each step
   shares a transaction with its version bump, so v11 only runs at stored version 10 — which
   is why this is last rather than urgent. It is a `DatabaseManager` change, so it cannot be
   done from a tests-only item; the honest test is the one W-J could not write, because
   asserting current behaviour means asserting data loss. Owns `DatabaseManager.swift` and
   `DatabaseTests.swift`, so it serialises against W-K.

### Serialise these

`project.pbxproj` is touched by **W-A, W-I, W-P, W-R** — one at a time, and hand-editing it
makes SourceKit noisy until the next build. `ContentView.swift` by W-F and W-G.
`HealthAppTests/DatabaseTests.swift` by W-J (**done**), **W-K** and **W-U** — W-K may now
start. `MLXOnDeviceClient.swift` by W-E (**done**) and **W-T**.
Only **one** migration is outstanding, **W-Q, which is now v16**: W-B took v15 on
2026-10-25.

### Standing verification facts for this repo

- **368 tests, 0 failures** in the `Fast` plan, measured 2026-10-26 at PR #51's head.
  Read the count from the `.xcresult`, never stdout. `PreRelease` has not been re-counted
  since it stood at 348.
- SwiftLint baseline **5**, and it must run from `HealthApp/`.
- Schema **v15** (W-B). `DatabaseMigrationTests` is the harness; add an idempotency case per
  version. The fixtures now start at **v10**, so the v11 encryption pass is covered.
- **Nothing in `MLXOnDeviceLLM/` has ever executed.** The simulator stubs out the load,
  generate and transfer bodies, so items 27, 28, 29 and 37 are typechecked and unit-tested
  but unrun. Typecheck with `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`;
  that build cannot reach the Keychain, so it will not run.
- Revert-and-confirm is worth the time: it caught **four** tests of mine that asserted
  nothing, including one whose own comment claimed otherwise.

### Six decisions waiting on you

**New (W-H):** should iPad have a real two-column Documents layout? The old one was dead
code and is now gone. Building it means `HealthTabView` adopting a `NavigationSplitView`
instead of its single nav bar with a segment switcher, which is a visible redesign of the
merged Records/Documents tab — not something to infer from a bug report. Today a document
opens in a sheet on every device, which works but wastes a 13-inch landscape.

§6 of the triage report has them in full. In short: sign off
`ITSAppUsesNonExemptEncryption = false` (legal call, BoringSSL via the AWS SDK is the
complication); internal vs external TestFlight for round one (WS-17 recommends internal,
which makes W-A..W-D the complete list); measure the 384 KiB/token KV constant during W-C;
hide the MedGemma 27B Mac path for the beta; re-verify item 32 during the W-C run.

---


## ▶ WS-17 triage (2026-10-25) — all 18 workstreams now run and merged

Report: `findings/WS-17-triage.md`. It was told **not** to replace this file: the prompt's
step 10 was written when nothing was fixed, and following it would have erased the record
below. It was also told to separate "fixed" from "evidence did not support", because for most
findings the code no longer matches the report *because it was fixed* — the prompt's
verification rule would otherwise have branded a dozen correct findings as hallucinations.

**It found two regressions I had shipped, both verified here before acting:**

| | What |
|---|---|
| `782b52db` (item 37) | `MLX.Memory.memoryLimit` was set to 55% of installed memory — **14.17 GB on a 24 GiB Mac, below MedGemma's 16.02 GB of weights**, on the one device class where that model is enabled. And mlx-swift's own doc for the property says "calls to malloc will **wait** on scheduled tasks if the limit is exceeded" — it blocks; releasing is `cacheLimit`'s job, which the code already set. My comment claimed the opposite. **The line is removed**; the context-window cap is the real mechanism and is unaffected. |
| `0fa45ec9` (item 13) | `loadConversations` already called `ErrorHandler`; my change added a second call with a differently-worded context, so the 5-second dedupe missed and **one failure raised two alerts**. The three message-save sites it also touched had no prior reporting and were correct. **Duplicate removed.** |

**Re-prioritisation accepted:** the 1024 app icon's alpha channel (filed P2 by two
workstreams) is an **upload blocker** — ITMS-90717 rejects it at validation, so it gated every
build to every tester while the rest of the submission checklist was being cleared. Verified
from the PNG IHDR (colour type 6), confirmed every pixel was already `alpha=255`, re-encoded
as colour type 2, and proved the 3,145,728 visible bytes are **identical**. `aps-environment`
also removed — there is no remote-push code at all.

**Still open and now itemised** (WS-17 found five P1s that never got item numbers).
**WS-08-02 is fixed**: `DocumentProcessor.failureReason(for:)` composes the recorded error's
description and its recovery suggestion, and both the detail view and the list row show it.
On a fresh install that now reads "No on-device vision model is downloaded… Go to Settings >
On-Device AI and download a Vision model" instead of a bare red badge. Session-scoped by
design — the status persists but `processingErrors` does not, so the detail view carries an
actionable fallback after a relaunch. **The reason is now durable too** (v15, W-B,
2026-10-25), so that fallback is reached only by a row that failed before the column existed.
Remaining: WS-01-01 + WS-03-02 (a stale title snapshot
clobbers live state, one work item), WS-06-03, WS-04-05 (`makeClientConfig` passes no
timeout). **WS-11-02 + WS-03-03 are addressed in source** by W-E — the token loop now reads
`isSuspendedForBackground` and stops at a token boundary — and that compiles for a device as
of 2026-10-26, but it is still unverified at runtime, which needs one. It also covers only
the streaming path; see W-E above.

**Also corrected:** item 40 closed WS-10-01 only — gold *as foreground* at 2.7:1 across ~25
sites (WS-10-02) is still open, and I had treated it as done. WS-13-07's evidence was false
while its conclusion stood: `UNUserNotificationCenter` appears 4× in `DocumentProcessor`, so
the app does post notifications — local ones, which need no `aps-environment`.

**Shortest honest path to a tester build, per WS-17: about half a day.** The icon and
`aps-environment` are done above. Remaining: show the failure reason on a failed document;
archive once on a device and run the three owner-only checks; TestFlight notes saying imports
need a vision model first.

---

## ▶ Where this stands (2026-10-23)

**Of the original 32 work items: 27 fixed, 1 partly fixed (21's file renaming), 4 untouched — plus 15 new items
(33–47) from the six workstreams that ran on 2026-10-24, of which 33, 34, 36, 45 and 47 are
fixed and 35 is half done.**

- Partly fixed: **21** (files imported before 2026-10-24 keep `<uuid>_<original name>` names;
  renaming them needs a migration that rewrites every stored path) **22 is now fixed.**
- Untouched: **25** (113 orphaned UI tests, deferred by decision 4), **30** (iPad portrait
  grid), **31** (restored reviews only on the Documents tab), **32** (the Import-tap
  mitigation, never re-verified in the app).

Items 10, 14 and 23 spent a day marked "fixed" when they were not — WS-13 and WS-16 found the
gaps and each was verified in source before being moved back. They are now genuinely done. The Status
column below is current as of this date — it had drifted badly, and item numbers are not
unique across the tables in this file, so edit those cells by hand rather than by script.

| Still open | Item | Sev |
|---|---|---|
| Extraction commit races a delete and resurrects a broken row | 11 | P1 |
| Unreadable fields written back over stored data | 12 | P1 |
| Four more `lastError` surfaces nobody reads | 13 (rest) | P1 |
| Thumbnails, tags and filenames still plaintext on disk | 21 (rest) | P1 |
| Privacy Policy and Terms claims | 22 (rest) | P1 (submission) |
| 113 orphaned UI tests | 25 | P2, deferred by decision 4 |
| iPad portrait grid overlap; dead master-detail | 30 | P2 |
| Restored reviews surface only on the Documents tab | 31 | P2 |
| Import tap mitigation not re-verified | 32 | P2 |

Workstreams never run: **WS-10** accessibility, **WS-11** performance, **WS-13** App Store
compliance, **WS-14** build/signing/TestFlight, **WS-15** test coverage, **WS-16** docs
drift, **WS-17** triage. WS-13 and WS-14 are the submission-critical pair and nobody has yet
looked at `PrivacyInfo.xcprivacy`, the encryption-exemption declaration, or whether an
archive signs.

Owner-only checks outstanding: one real Bedrock call (decision 5), and the keychain
migration on a genuine device upgrade.

### A verification lesson from the MLX work

`MLXOnDeviceClient.swift` and `MLXModelDownloadManager.swift` compile in the simulator —
their types, published state and pure helpers are outside the guards, and `MLXOnDeviceModels`
reaches 57% line coverage. What is `#if !targetEnvironment(simulator)` is the MLX imports and
the **bodies** that load a model, generate, and transfer bytes: a simulator build replaces
those with stubs, so **an error inside one of them compiles clean and no test can reach it.**
(An earlier version of this note said the files compile out entirely. That was too strong;
WS-15 corrected it. The operational advice is unchanged.) Typecheck them with:

```
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Nothing in those files can be exercised at runtime without a physical device. Items 27, 28
and 29 are therefore **typechecked and unit-tested but never run**: each fix deliberately
puts its decision rule in a plain value type (`MLXContextBudget`,
`MLXDownloadRetryBudget`) so the rule itself is testable in the simulator even though the
code around it is not. The MLX-side wiring still needs a device.

## ▶ Verified in a running app: v13 durable review queue (2026-10-23)

Both checks confirmed on iPad Pro 11-inch (M5); report in
`findings/V13-RESTORE-VERIFICATION.md`.

| Check | Verdict |
|---|---|
| A row is written when the review sheet appears | CONFIRMED |
| Force-quit then relaunch brings the review back | CONFIRMED, **but only once the Documents tab is opened** |
| Cancel keeps the row; the review returns next launch | CONFIRMED, same caveat |
| Completing the import deletes the row | CONFIRMED |
| A real v12 database migrates to v13 with data intact | CONFIRMED — "Migration needed from v12 to v13", table recreated, 4 documents and 1 lab record survived |

**Claim corrected.** The v13 commit says un-reviewed imports are "offered again on
launch". That is too strong: `restorePendingImportReviews()` runs from a `.task` inside
`DocumentsView`, and the sheet is attached to the same view, so after a force-quit the app
opens on Records and nothing surfaces until the user taps Documents. The data is never
lost — which was the actual defect — but the review appears on the Documents tab, not at
launch. Making it surface anywhere would mean moving both the restore and the sheet to the
root view; that is the same view-scoped-presentation family as item 9 and is filed below
rather than done speculatively.

| New | Title | Sev |
|---|---|---|
| 31 | Restored reviews surface only on the Documents tab, not at launch | P2 |
| 32 | Import tapped at "Import 3 of 10" with no choices made left the sheet up and wrote nothing; it worked after a value was selected. Most likely the sheet being re-presented across the async save — mitigated by dismissing before the await, **not yet re-verified in the app** | P2 |

## ▶ Fix passes 1–2 — landed and verified in a running app

**Verified on the iPad simulator** (report: `findings/FIX-PASS-1-VERIFICATION.md`):

| Check | Verdict | Evidence |
|---|---|---|
| Import stops retrying | **CONFIRMED FIXED** | Log shows attempt 1/3 → 2/3 → 3/3 → "Maximum retry attempts reached, marking as failed", then silence for ~65s. A second, differently-failing file also stopped at 3/3 |
| No fabricated lab record | **CONFIRMED FIXED** | "Lab report yielded no parseable values — importing no health data rather than a placeholder"; Records still reads "No lab results" |
| Document failures visible | **PARTIAL → now completed** | A thumbnail failure raised an alert, but a 0-byte import did not: `DocumentImporter` has its *own* `lastError`, which pass 1 never wired up. Fixed in pass 3 below |
| Substituted value not auto-imported | **CONFIRMED FIXED** | "Reconciler: 10 candidates → 2 auto-accepted, 3 need review". Auto-accepted were exactly Sodium and Chloride (unit + range present); review held exactly Creatinine, Glucose and Potassium (range and/or unit missing). Deterministic parser path only — the mock returns `{}`, so the LLM path is untested |

### Pass 3 — gaps the verification exposed, now fixed

- **`DocumentImporter.lastError` now reports through `ErrorHandler`.** Pass 1 wired up
  `DocumentManager` only, so per-file batch import failures stayed silent — exactly the
  0-byte case above.
- **A registry-completed value is no longer "Recommended" or pre-selected.** Gating
  auto-accept was not enough: the review sheet still starred Glucose as
  "85 mg/dL, Expected 70-100" and pre-selected it, when the document stated neither. One
  tap on *Accept All Recommended* imported the app's assumption as fact. `BloodTestImportCandidate`
  now carries `unitWasSubstituted` / `referenceRangeWasSubstituted`, and `isRecommended`
  requires both to be false. The value stays selectable — the user may know the unit is
  right — it just no longer wears a star.

### Still open from the verification (not regressions)

| Finding | Severity | Note |
|---|---|---|
| After 3 failed attempts the list and detail sheet keep showing "Pending" with no message until you switch tabs | P2 | Same view-staleness family as item 9. No longer infinite, but still silent in the moment |
| The OCR layout pass emits duplicate candidates with misread units (Creatinine "0.9 ng/dL" and "0.9 mg/dL") | P2 | Forces a "Multiple values found" review, which is the safe outcome, but the unit misread is real |
| Skip/Done on the Document Type sheet re-triggers processing, starting a fresh 1/3 cycle | P2 | Wasteful, and confusing after a failure |

## ▶ Fix pass 1 — what each change was

Five work items fixed. iPhone and iPad builds succeed, **258 tests pass, 0 failures**
(confirmed from the `.xcresult` — the console only prints the 2 UI tests because the unit
bundle runs parallelized), SwiftLint unchanged at 5 pre-existing violations. Four source
files, +94/−53.

| Item | What changed | How to check it in the app |
|---|---|---|
| 7 · WS-03-01 | Vision continuation now claims a shared gate before resuming, on both the OCR and perspective paths, so Vision invoking the completion handler *and* throwing can no longer trap the process | Defensive — hard to trigger on purpose. What you should see is **no change** in normal imports |
| 26 · WS-09-01 | `addToQueue` now carries `retryCount` across a re-queue, so `maxRetryAttempts` actually bites | On a fresh install with **no on-device vision model**, import a lab PDF. Before: "Pending" forever, silently, retrying every few seconds. Now: it stops after 3 attempts and reports a failure |
| 2 · WS-05-04 | A lab report with no parseable values no longer gets a fabricated `"Lab Report Processed"` row; the builder is deleted and the item-mapping path throws `noValuesExtracted` instead | Import a lab report the parser can't read. Before: a blood test appeared in Records summarised "All normal". Now: no record is created, and you're told nothing was extracted |
| 13 (partial) · WS-08-01/04 | `DocumentManager.lastError` now reports through `ErrorHandler` from `didSet`, so all ~12 previously-silent assignment sites surface | Cause any document failure — import an unreadable file, or delete with the DB locked. Before: nothing happened. Now: an error alert |
| 17 · WS-04-01 | Bedrock model id corrected from the dotted `claude-sonnet-4.5-…` to `claude-sonnet-4-5-20250929-v1:0` | **Needs your AWS credentials.** Configure Bedrock and send a chat message. If it now answers, that confirms the id was the whole problem |

**What this pass deliberately did not touch**: anything gated on decision 1 (the parser's
unit/reference-range fallback, items 1, 3, 4, 5, 6). Those are the two P0s' real home and
they need your answer first — the fix is structurally different depending on whether
auto-accept survives.

**Known limitation introduced**: `noValuesExtracted` is deterministic, but the retry path
still retries it 3 times before failing. Harmless now that the counter works, wasteful in
principle. Filed as a follow-up rather than fixed, because classifying errors as
retryable/non-retryable is a bigger change than this pass warranted.


**Status**: WS-00, Batch A (01, 02, 03, 07), Batch B (04, 05, 06, 08) and Batch C pair 1
(09, 12) complete (2026-10-22). **Paused here at the owner's request.**
Remaining: WS-10, WS-11, WS-13–WS-16, then WS-17 formal triage.

WS-09 is the only workstream so far to have **run the app**. Its 29 screenshots are in
`findings/WS-09-screenshots/`. Note for whoever resumes: the iPhone 17 Pro simulator was
occupied by an unrelated `BisonVoice` test run, so WS-10 needs a different iPhone device.
**Owner of this file**: WS-17 (triage) replaces the worklist wholesale; fix agents update
only the Status column of their own row; anyone may append to "Found during fixing".

**Filed**: 149 findings — P1=41, P2=70, P3=38, P0=0 as filed.
**After orchestrator re-grade: 2 P0.** See "Re-grades" below. The worklist merges the
P0/P1 set into 24 work items; the P2/P3 remainder stays in the findings files until WS-17.

---

## ▶ Batch C pair 2 and Batch D (2026-10-24) — all 18 workstreams now run

WS-10, WS-11, WS-13, WS-14, WS-15 and WS-16 complete. Findings: WS-13 P0=1 P1=4, WS-14 P1=3,
WS-11 P1=3, WS-15 P1=4, WS-10 P2=8 (no P0/P1), WS-16 P1=3.

**Two reviews independently reached the same top blocker: there is no app-level
`PrivacyInfo.xcprivacy`.** Verified: none exists anywhere under `HealthApp/`, and the app uses
UserDefaults and file-timestamp APIs that need declared reasons. `ITSAppUsesNonExemptEncryption`
is also absent, so every TestFlight build stops at "Missing Compliance". Both confirmed by hand.

### Items wrongly marked fixed — found by WS-13 and WS-16, each verified in source

| # | What the tracker claimed | What is actually true |
|---|---|---|
| 10 | Reset Database fixed | **NOW FIXED (2026-10-24).** Was: only the in-memory half. `performDatabaseReset` deletes the database, its sidecars and migration backups, then says "All health data has been permanently deleted" while document files in `Documents/Imported` and plaintext thumbnails in `Documents/Thumbnails` remain. `DocumentManager.cleanupOrphanedFiles()` has **no callers**. `SettingsView.swift:50` still promises "A backup will be created first", which nothing does. |
| 14 | All 14 discarded error paths report | **NOW FIXED (2026-10-24).** Was: `ChatDetailView.swift` `emptyStateView` still had `Task { _ = try await chatManager.startNewConversation() }`. Missed site. |
| 23 | Cloud-send consent fixed | **NOW FIXED (2026-10-24)** — policy moved to `CloudProcessingConsent` and enforced fail-closed by the send paths. Was: an `@AppStorage` **inside `ChatDetailView`** — all three references are in that one file. `AppointmentPrepManager.swift:148` calls `getAIClient()` and sends health context with no consent at all. Same view-scoped mistake as item 9. |

### New items

| # | Title | Sev | Source |
|---|---|---|---|
| 33 | No app-level `PrivacyInfo.xcprivacy`; required-reason APIs undeclared | **P0** (submission) | **fixed** — `HealthApp/PrivacyInfo.xcprivacy`, verified present and parsed in the built bundle |
| 34 | `ITSAppUsesNonExemptEncryption` absent — every TestFlight build blocks on Missing Compliance | P1 (submission) | **mechanism fixed**, value set `false` and verified in the built Info.plist — ⚠️ **the value is a legal declaration and needs the owner's sign-off**; see the comment in `Info.plist` for the BoringSSL complication |
| 35 | Release path not repeatable: `CURRENT_PROJECT_VERSION = 1` hard-coded in **6** places (WS-14 said 8; recounted), no CI, no test plan, no export options, no distribution identity | P1 | **build numbering fixed** — `Scripts/archive.sh` derives it from the commit count, proven to reach `CFBundleVersion` (1 → 584). Still open: CI, test plan, `ExportOptions.plist`, distribution identity |
| 36 | **Session rebuild re-prefills the entire conversation.** `AIChatManager` builds `mlxConversationHistory` from all of `conversation.messages`; `ConversationContextBuilder` is never applied on this path. My own comment in `MLXOnDeviceClient.swift` claims "history trimmed to fit" — it is false, and commit 6ad65405 *added* a rebuild trigger, so it made this fire more often while asserting it was handled | P1 | **fixed** — `AIChatManager` now runs the conversation through `ConversationContextBuilder` with a reserve covering the real reply budget and the rules block; the false comment is corrected |
| 37 | No device-aware memory ceiling for the KV cache: `MLX.Memory.memoryLimit` is never set and the context slider reaches 65,536. Item 27 sized patient data within the window but never asked whether the window fits the device | P1 | WS-11-01 |
| 38 | `AIResponseCleaner.clean`/`cleanConversational` runs ~35×/s on the full accumulated text — once per 50 ms from the client and again per render in the bubble's `body`. Measured on Mac: 15 ms at 30K chars, >50% of the main thread. (This answers WS-06-11: the amortized repetition scan was the right fix to the wrong function — the scan is 1.4 ms at 30K) | P2 | WS-11-07 |
| 39 | Doctor personas claim "board-certified" and instruct the model to suppress disclaimers and AI disclosure, against guideline 1.4.1 and the shared safety rules | P1 | WS-13-02 |
| 40 | White on `BisonTheme.gold` is 2.91:1 light and **1.89:1 dark** — fails AA and even AA-large. `BisonTheme.inkOnGold` already exists and gives 5.83:1 / 8.97:1. Ratios recomputed by hand; a one-token swap at ~6 sites, one of them the chat user bubble | P2 (under-graded; cheapest high-value fix in the review) | WS-10 |
| 41 | 9 regressions injected at once left all 291 unit tests green (mutation-tested): v11 encryption migration, migration-backup deletion, reprocess metadata merge, stuck-`.processing` startup sweep, streaming throttle guards, privacy-category persistence, the P0-1 PDF page-index fix | P1 | WS-15-01..04 |
| 42 | Tests that cannot fail, with `file:line` in the findings — including **my own** `MLXDownloadRetryBudget` reset test, whose baseline claim is unobservable (fixed 2026-10-24), and `AIChatManagerTests.swift:94` asserting a count `>= 0` | P2 | WS-15-06 |
| 43 | No test constructs `MLXModelDownloadManager`, so deleting the `recordProgress` call leaves the suite green. Extracting the rule makes the rule testable, not the wiring — and both MLX bugs that motivated it were wiring bugs | P2 | WS-15-07 |
| 44 | Hosted tests use `DatabaseManager()` / `FileSystemManager()` with no URL (3 sites each), writing to the real app container rather than a temp directory | P2 | WS-15-08 |
| 45 | `CLAUDE.md` says database version 10, 12 and 11 in five places (real: 13) and still claims "no iCloud/CloudKit backup" and "all data on-device" — an agent reading it could re-harden the key to `ThisDeviceOnly` and reintroduce item 8 | P1 (agent-facing) | **fixed** — versions corrected to 13, the backup section now states the real posture with an explicit warning against re-hardening the key, and the broken build/test/lint commands work as written |
| 46 | Six documents claim encryption unqualified while thumbnails, tags and on-disk filenames are plaintext; build/test commands in CLAUDE.md, AGENTS.md, README and CONTRIBUTING fail as written (wrong project name, scheme, a simulator that is not installed, missing `cd HealthApp`); `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` is referenced but absent; `.claude/CLAUDE.md` is tracked lowercase as `claude.md` | P2 | WS-16 |
| 47 | Privacy Policy line 33 says loading a model contacts Hugging Face. Commit 330bebf9 removed that yesterday — my own fix made the copy inaccurate | P2 | **fixed** — Privacy Policy and the On-Device AI settings footer both corrected |

**Privacy-manifest reason codes, verified rather than recalled.** WS-13 said its code
strings came from its own knowledge, not a quote. Apple's documentation pages render via
JavaScript and return only a title to a fetch, so two independent sources were cross-checked
instead: they agree on `CA92.1` (user defaults reachable only by this app), `C617.1` (files in
the app's own container) and `3B52.1` (a file the user granted access to via the picker), and
disagree only on `0A2A.1`, which this app does not need. `DDA9.1` is deliberately omitted — no
file timestamp is displayed in the UI. A per-call-site audit decided which applied: `AppLog`
and `cleanupOldThumbnails` read container timestamps (C617.1), and `DocumentImporter`'s
`attributesOfItem` runs on a picked URL (3B52.1) — it reads only `.size`, but the API itself is
required-reason, so the declaration covers the call.

**Corrections to agent reports, each checked against source:** WS-14's `CURRENT_PROJECT_VERSION`
count is 6, not 8. WS-16's `@unchecked Sendable` count of 4 is right (the plan says 5, WS-03
said 3 — the difference is the `ContinuationGate` added by the item-7 fix). WS-15 corrected
*me*: the MLX files are not wholesale `#if`-wrapped, only their bodies are.

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
| 09 | iPad & adaptive layout | **complete (ran the app)** | [WS-09-ipad-adaptive.md](findings/WS-09-ipad-adaptive.md) | 0 | 1 | 7 | 7 |
| 10 | Accessibility | **complete (ran the app)** | [WS-10-accessibility.md](findings/WS-10-accessibility.md) | 0 | 0 | 8 | 7 |
| 11 | Performance & memory | **complete (measured)** | [WS-11-performance.md](findings/WS-11-performance.md) | 0 | 3 | 11 | 1 |
| 12 | MLX model lifecycle | **complete** | [WS-12-mlx-lifecycle.md](findings/WS-12-mlx-lifecycle.md) | 0 | 3 | 8 | 3 |
| 13 | App Store compliance | **complete** | [WS-13-appstore-compliance.md](findings/WS-13-appstore-compliance.md) | 1 | 4 | 8 | 1 |
| 14 | Build, signing & TestFlight | **complete** | [WS-14-build-testflight.md](findings/WS-14-build-testflight.md) | 0 | 3 | 5 | 2 |
| 15 | Test coverage | **complete (mutation-tested)** | [WS-15-test-coverage.md](findings/WS-15-test-coverage.md) | 0 | 4 | 8 | 3 |
| 16 | Docs drift | **complete** | [WS-16-docs-drift.md](findings/WS-16-docs-drift.md) | 0 | 3 | 7 | 5 |
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
| 1 | WS-05-01 +07 +08 +09 | Unit and reference range silently fall back to the hardcoded registry, and `isAbnormal` is computed from the substituted range. Also: a dashed date in a neighbouring cell becomes the reference range; `5,4` parses as 54 | **P0** | BB | M | `Services/BloodTestMappingService.swift`, `Services/LabReportParser.swift` | **fixed** (bf6aff50, 65ec1f23) |
| 2 | WS-05-04 | A document with zero parsed values is saved as a real blood test holding a fabricated "Lab Report Processed" row, summarised "All normal" | **P0** | BB | S | `Services/DocumentProcessor.swift` | **fixed (pass 1)** |
| 3 | WS-05-02 | Urinalysis section state never resets, so serum creatinine is auto-accepted as *Urine* Creatinine and ferritin is dropped | P1 | BB | M | `Services/LabReportParser.swift` | **fixed** (65ec1f23) |
| 4 | WS-05-11 +12 +10 | Auto-accept UX: abnormal results default to "Will Ignore" so one tap saves a record reading "All normal"; the only notice is a 12 s toast published *before* the commit; the review sheet never shows the test date | P1 | BB | M | `Views/BloodTestImportReviewView.swift`, `Services/DocumentProcessor.swift` | **fixed** (90f34aa8) |
| 5 | WS-05-03 | Duplicate heuristic compares analyte names only, plus an import-date fallback: five historical labs imported in one sitting save one | P1 | BB | M | `Managers/HealthDataManager.swift`, `Services/BloodTestMappingService.swift` | **fixed** (c58dd33d) |
| 6 | WS-05-06 | Review queue is in-memory only: Cancel or relaunch discards the document's extracted values, including auto-accepted ones, and nothing re-opens them | P1 | BB | M | `Services/DocumentProcessor.swift` | **fixed** (05c1d940, schema v13) |

### Crash and data loss

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 7 | WS-03-01 | Vision continuation double-resumes → uncatchable `SWIFT TASK CONTINUATION MISUSE` trap on the import path; the page-loop `catch` written to degrade gracefully cannot catch it | P1 | BB | S | `Services/NativeDocumentExtractor.swift` | **fixed (pass 1)** |
| 8 | WS-02-01 + WS-07-03 + WS-02-02 | Restore to a new device silently destroys all health data: the DB is in device backups, the `WhenUnlockedThisDeviceOnly` key is not, and the code mints a fresh key over the restored database | P1 | BB | M | `Database/DatabaseManager.swift`, `Utils/Keychain.swift` | **fixed** (3c857bbb) |
| 9 | WS-06-01 + WS-06-04 | Tapping Records destroys `DocumentsView`; the review sheets fire only on `.onChange` with no `initial:`, so a review completed off-screen never appears and every later review jams behind it. Values needing review are never imported | P1 | BB | M | `Views/HealthTabView.swift`, `ContentView.swift` | **fixed** (90f34aa8) |
| 10 | WS-06-02 + WS-02-06 + WS-02-07 | Reset Database says "All health data has been permanently deleted" while the PHI is still in memory and on screen, and a Save writes it back; it also promises a backup it never makes and leaves documents on disk; migration backups are undeletable | P1 | BB | M | `Views/SettingsView.swift`, `Database/DatabaseManager.swift` | **partly fixed** (65ec1f23 — in-memory PHI + migration backups); files on disk and the false backup promise remain (item 10 row above) |
| 11 | WS-01-02 + WS-03-06 | Extraction commit uses a pre-AI-call snapshot with no cancellation re-check before `INSERT OR REPLACE`: deleting mid-extraction resurrects a broken row, user edits overwritten | P1 | BB | M | `Services/DocumentProcessor.swift` | **fixed** (ffc8c912) — extractor rethrows cancellation, processor re-checks, and `saveMedicalDocument(requireExistingRow:)` puts the existence check and the write in one transaction |
| 12 | WS-02-03 + WS-01-04 | Unreadable fields read as empty then written back over stored data; `validationFailed` swallowed so an invalid report finishes "successfully" | P1 | BB | M | `Database/DatabaseManager+Documents.swift`, `Services/DocumentProcessor.swift` | **fixed** (ffc8c912) — `unreadableFields` recorded on read, full-row writers refuse while it is non-empty (`DatabaseError.lossyWriteRefused`), and the AI-context selector uses the partial updater |

### Failures the user cannot see

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 13 | WS-08-01 + WS-08-04 + WS-05-05 + WS-08-07 | **Partly fixed (pass 1: DocumentManager only)** — `lastError` is written at ~12 sites in `DocumentManager` and read by no view; same for `DocumentImporter`, `DocumentExporter`, `ConversationExporter`, `MLXOnDeviceClient`, and `AIChatManager.errorMessage`. Every import failure is invisible, and a *failed load* renders as "you have no documents" | P1 | BB | L | `Managers/DocumentManager.swift`, `Utils/Document*.swift`, `Views/DocumentListView.swift`, `Views/DocumentGridView.swift` | **fixed** (0fa45ec9) — both exporters and all four `AIChatManager.errorMessage` sites report; a failed load no longer renders as "No Documents". `MLXOnDeviceClient.lastError` deliberately left: one site, inside `testConnection()`, whose Bool return is the signal and which has no UI caller for this client |
| 14 | WS-00-01 | 14 discarded error paths in `Task { try await … }`, incl. vitals that appear saved but are not | P1 | BB | M | `ContentView.swift`, `Views/VitalsListView.swift`, `Views/ChatDetailView.swift`, `Managers/AIChatManager.swift` | **partly fixed** (c58dd33d); `ChatDetailView.emptyStateView` site missed |
| 15 | WS-08-05 | Lab values the user just reviewed or typed are dropped silently when `addBloodTest` refuses them | P1 | BB | M | `Managers/HealthDataManager.swift` | **fixed** (8cf5ee97) |
| 16 | WS-08-06 + WS-08-12 | Global error layer: `.warning` severity is queued and never displayed (drains only when another alert is dismissed); 5 s dedupe can swallow a Retry failure; a second error overwrites an unacknowledged first. Causes are also mislabelled — Bedrock errors become "Network error" | P2 | BB | M | `Managers/ErrorHandler.swift` | **fixed** (d5c040cc) |

### AI providers

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 17 | WS-04-01 | Bedrock model ID is `claude-sonnet-4.5-…` with a dotted version where Anthropic uses hyphens (`claude-sonnet-4-5-20250929-v1:0`); the same repo writes `claude-3-5-sonnet-…` correctly. Probably breaks all Bedrock chat *and* cloud vision extraction, reported as "check your internet" | P1 | BB | S | `Services/BedrockClient.swift` | **fixed (pass 1) — still needs one real Bedrock call to confirm** |
| 18 | WS-04-02 + WS-08-03 | Offline gate is not provider-aware (`ChatDetailView.swift:200`), so airplane mode disables the on-device model — the one path that needs no network. Banner also claims document processing is unavailable | P1 | BB | M | `Views/ChatDetailView.swift`, `Managers/AIChatManager.swift` | **fixed** (a7c44147) |
| 19 | WS-04-03 | `compressHealthDataContext` blind-truncates a sorted JSON blob from the end, so `personal_info` (allergies, medications, conditions) is dropped before bulky document text | P1 | BB | M | `Managers/AIChatManager.swift` | **fixed** (a7c44147) |
| 20 | WS-04-04 + WS-07-01 | No "data, not instructions" guard on the Bedrock or OpenAI-compatible paths (only MLX has `compactChatRules`), and `textual`'s `ImageLoader.shared` fetches any model-emitted image URL with no allowlist — together an exfiltration chain | P1 | BB | M | `Services/BedrockClient.swift`, `Services/OpenAICompatibleClient.swift`, `Views/ChatDetailView.swift` | **fixed** (21666379) |

### Privacy and claims

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 21 | WS-02-04 +05 +12 + WS-07-02 | Plaintext PHI at rest: `patient_name` in the `metadata` column, page-1 thumbnails on disk and in backups, free-text tags, original filenames in on-disk names | P1 | BB | M | `Database/DatabaseManager+HealthData.swift`, `Services/BloodTestMappingService.swift`, thumbnail writer | **fixed** — thumbnails encrypted with a legacy-plaintext fallback that re-encrypts in place; new imports stored as `<uuid>.<ext>` so the filename no longer carries the patient's own words; `tags` encrypted by schema **v14**. Remaining: renaming files imported before this needs a path-rewriting migration, still deferred |
| 22 | WS-07-06 | 11 privacy claims the code does not support: README "never leaves the device"; backup removed "for HIPAA compliance" contradicting the non-HIPAA disclaimer; `NSHealthUpdateUsageDescription` claims write access the app never uses (`toShare: []`) | P1 | SB | M | `README.md`, `Views/PrivacyPolicyView.swift`, `Views/TermsOfServiceView.swift`, `project.pbxproj` | **fixed** — Apple Health section added (12 types, read-only, never written), encryption claim made exact including the one thing that is not encrypted, Reset Database wording made concrete, policy date corrected, HealthKit usage string rewritten and verified in the built Info.plist. **Terms date left at July 3 deliberately: git shows that file genuinely has not changed since, so WS-16 was wrong to pair them.** |
| 23 | WS-07-04 | No cloud-versus-on-device indicator in chat, and nothing asks before the first cloud send | P1 | BB | M | `Views/ChatDetailView.swift`, provider settings views | **partly fixed** (8cf5ee97 — indicator + consent in ChatDetailView only); Appointment Prep sends with no consent |
| 24 | WS-07-05 | Tapping a genetics reference sends gene + diplotype in a query string to `pharmdog.clinpgx.org`, undisclosed | P1 | BB | S | `Models/GeneticTestResult.swift` | **fixed** (21666379) |

### Test infrastructure

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 25 | WS-01-08 | 113 UI test functions in 6 files are orphaned from the UI test target and never compile; stale selectors must be fixed to re-add them. Blocks all UI and accessibility verification | P2 | PP | L | `HealthApp.xcodeproj/project.pbxproj`, `HealthAppUITests/*` | todo |
| — | WS-00-02 | Review plan's iPad build destination malformed | P2 | — | S | plan + fix protocol | **fixed** |

### Added by Batch C pair 1

| # | ID(s) | Title | Sev | Class | Eff | Files (ownership) | Status |
|---|---|---|---|---|---|---|---|
| 26 | WS-09-01 | **Import retries forever and silently** when no on-device vision model is present — the fresh-install default. `addToQueue` builds a new queue item with `retryCount = 0` each time, so `maxRetryAttempts` never bites: 13+ "attempt 2/3" cycles in ~50 s, document stuck "Pending", no error shown. Observed live on iPad. An App Review tester hits this first | P1 | BB | M | `Services/DocumentProcessor.swift` | **fixed (pass 1)** |
| 27 | WS-12-02 | **The on-device safety rules are evicted from context.** `compactChatRules` (treat patient data as facts; never tell the user to change a medication) sits in the head of the system block, and `RotatingKVCache(maxSize:, keep: 4)` keeps only the first 4 tokens. With 90% of the budget given to patient data, overflow comes within a turn or two and the guard silently stops applying | P1 | BB | M | `MLXOnDeviceLLM/MLXOnDeviceClient.swift` | **fixed** (6ad65405) |
| 28 | WS-12-01 | Every model load calls `hub.snapshot`, so the on-device path contacts huggingface.co on each load (undisclosed — WS-07's egress row covers only the one-time download). Only `NSURLErrorNotConnectedToInternet` falls back to local files, so a captive portal, DNS failure or timeout fails the load outright | P1 | BB | M | `MLXOnDeviceLLM/MLXOnDeviceClient.swift`, privacy policy | **fixed** (330bebf9) |
| 29 | WS-12-03 + WS-12-07 | A shared retry counter that never resets — and is consumed by backgrounding — deletes the whole model directory including finished shards on the third hit, forcing a ~16 GB re-download. Downloads also start on cellular on one tap, with `allowsExpensiveNetworkAccess`/`allowsConstrainedNetworkAccess` explicitly overriding Low Data Mode | P1 | BB | M | `MLXOnDeviceLLM/MLXModelDownloadManager.swift` | **fixed** (e825f276) |
| 30 | WS-09-02 + WS-09-03 | iPad portrait document grid: four flexible columns hold fixed 200 pt tiles in ~118 pt columns, so tiles overlap and the first clips. The iPad master-detail for Documents is dead code — `HealthTabView` always passes `embedInNavigation: false`, so landscape gets a full-width list and detail opens as a small form sheet | P2 | PP | M | `Views/DocumentGridView.swift`, `Views/HealthTabView.swift` | after 9 |

**Live confirmations from WS-09** — these were statically confirmed earlier and are now
reproduced in a running app, which raises their priority because they are easy to hit:
- **Item 9** (tab-switch destroys the import review): confirmed live. Log says
  "6 groups need review — showing review sheet" and no sheet appears; the document reads
  Completed with zero values imported. A second import enqueues behind the first and also
  imports nothing. Only Reprocess Document recovers.
- **Item 6** (review queue not durable): Cancel discarded all 10 extracted values
  including the 4 auto-accepted ones, with nothing in the UI offering to re-open them.
- This also refines WS-01's "P1-8 holds for retry timers": the static review cleared the
  retry path, and the live run found the infinite-retry hole now filed as item 26.

**Still unexercised after pair 1**: Split View / Slide Over / Stage Manager (the tools
offered no way to drag or resize windows), hardware-keyboard Tab/Esc, pointer hover,
drag-and-drop, and the Vitals, Genetics, Imaging, Storage, Export and Privacy/Terms
screens. WS-09's adaptivity table marks each one untested.

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
| 1 | **Should the app auto-accept any parsed lab value without review?** Items 1–6 all stem from auto-accept plus a lossy parser. | (a) require review for every imported value until the parser is trusted; (b) keep auto-accept but only when unit *and* range came from the document, never from the registry; (c) keep as-is and fix the individual bugs | (b) — it preserves the feature and makes the P0 structurally impossible: no substituted unit or range may ever be auto-accepted | **(b)** — auto-accept only when the unit *and* range came from the document. Done. |
| 2 | The core privacy claim ("health data never leaves the device") is false whenever a cloud provider is configured. Fix the claim or the product? | (a) reword to "on-device by default, cloud only if you configure it"; (b) ship v1 on-device only | (a) | **(a)** — reword the claims. Partly done (README, HealthKit string); Privacy Policy and Terms remain. |
| 3 | Device backups hold the encrypted DB but not the key, so a restore yields unreadable data. | (a) exclude the DB from backup too — a restore starts clean and the loss is explicit; (b) keep it and move the key to a syncable class; (c) build an explicit encrypted export/import | (a) for beta, (c) before public release | **(b)** — make the key restorable (synchronizable keychain class). Done; the upgrade path is still unverified on a real device. |
| 4 | Re-enabling the 113 orphaned UI tests is L-sized with stale selectors. Before beta or after? | (a) before; (b) after, with manual walkthroughs for the beta | (b) for beta, (a) before submission — and WS-09/WS-10 must then be told the tests don't exist | **(b)** — after the beta, with manual walkthroughs meanwhile. WS-09/WS-10 are told the UI tests do not exist. |
| 5 | **Is Bedrock in scope for the beta at all?** If item 17 confirms it never worked, nobody has been using it. | (a) fix the ID and keep it; (b) hide Bedrock for the beta and ship MLX + OpenAI-compatible | (a) if the one-line fix works; (b) if it needs more, since items 19, 20 and 23 all get smaller | **(a)** — keep Bedrock with the corrected id. Owner will confirm with one real call. |

---

## Found during fixing

| Date | Found by | ID | Title | File:line | Sev | Status |
|---|---|---|---|---|---|---|
| 2026-10-23 | item 28/29 work | — | **A simulator build typechecks none of the MLX code.** Both MLX files are inside `#if !targetEnvironment(simulator)`, so every MLX review and fix before this one was validated by a build that skipped the code under change. Use a `generic/platform=iOS` build. | `MLXOnDeviceLLM/*` | process | **fixed** — recorded at the top of this file and in the fix protocol |
| 2026-10-23 | item 29 work | — | Cancelling a download now *keeps* the bytes instead of deleting them, so Cancel means stop rather than stop-and-erase. Deliberate, and paired with a Resume/Remove row — but it is a visible behaviour change the owner may want to weigh. | `MLXModelDownloadManager.swift` | note | by design |
| 2026-10-23 | item 27 work | — | Context overflow still has no on-screen notice. It reaches the log and the response metadata (`contextWindowRebuilt`) only. | `MLXOnDeviceClient.swift` | P3 | open |
