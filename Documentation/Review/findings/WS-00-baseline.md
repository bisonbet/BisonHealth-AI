# WS-00 — Baseline: build, test, lint, inventory

- **Agents / models**: Part A (builds + tests) Sonnet; Part B (lint + inventory) Haiku; merged and independently verified by the orchestrating session (Opus)
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (branch `main`)
- **Scope actually covered**: incremental + fresh-DerivedData builds for iPhone and iPad; unit + UI suites twice on iPhone and once on iPad; SwiftLint with and without the baseline; full source/test inventory; verification of the plan's declared repo facts
- **Scope not covered**: cold build from a clean checkout; iPad warnings captured independently (the iPad build recompiled nothing, so its 0-warning result is not evidence); iOS 27.0 runtime; code-coverage instrumentation; device (non-simulator) runs
- **Verdict**: the project is in good health as a starting point — it builds on both device families and all 258 tests pass, twice. The baseline surfaced one substantive defect cluster (14 compiler-identified discarded error paths) and one defect in the review plan itself, both recorded below.
- **Counts**: P0=0 P1=1 P2=1 P3=0 (dropped: 0)

## Verification note

Every number in this file was re-checked by the orchestrating session against the raw
artifacts rather than taken from the subagents' summaries: `BUILD SUCCEEDED` / `TEST
SUCCEEDED` counts from the xcodebuild logs, test case results parsed from the three
`.xcresult` JSON exports, lint violations recounted from the two JSON reports, and the
warning sites read in source. One Part B claim was **not** verifiable and is excluded
from this report: that the 95-entry baseline file contains "75 force_unwrapping, 20 IUO,
39 of them stale". The baseline entries are `{text, violation}` shaped and do not expose
rule ids at the top level. The conclusion that the baseline has drifted stands on the
simpler fact that it holds 95 entries against 61 live violations.

---

## Findings

### WS-00-01 — 14 discarded error paths on user-data save and delete flows
- **Severity**: P1 · **Confidence**: CONFIRMED (the error is discarded; whether each throw fires in practice is for WS-02/WS-08 to establish) · **Effort**: M
- **Location**: `HealthApp/HealthApp/ContentView.swift` (10 sites), `HealthApp/HealthApp/Views/VitalsListView.swift:34` and `:49`, `HealthApp/HealthApp/Views/ChatDetailView.swift:148`, `HealthApp/HealthApp/Managers/AIChatManager.swift:1027`
- **Scenario**: every site is a `Task { try await … }` whose thrown error is discarded —
  the compiler flags it as `unstructured throwing task … is not used`
  (`[#NoUseUnstructuredThrowingTask]`). When the awaited call throws, the user's action
  silently does nothing. Concretely:
  - `VitalsListView.swift:34,49` — `savePersonalInfo(updatedInfo)` throws → the vital the
    user just entered is never persisted, and the sheet dismisses as though it saved.
    Indistinguishable from data loss from the user's side.
  - `ContentView.swift:322` — `deleteBloodTest(bloodTest)` throws → the delete silently fails.
  - `ContentView.swift:1440` — `startNewConversation()` throws → no conversation, no error,
    the button appears dead.
  - `ContentView.swift:1446` — `deleteConversation(conversation)` throws → silently fails.
  - `AIChatManager.swift:1027` — `updateConversation(conversation)` throws → the
    conversation's `includedHealthDataTypes` / `includedPersonalInfoCategories` are not
    persisted. **This is the same surface as prior finding P1-5 ("privacy opt-outs
    silently revert to include everything")**, which makes it the highest-priority site
    in the cluster.
- **Evidence**:
  ```swift
  // VitalsListView.swift:32-37
  onSave: { updatedInfo in
      Task {
          try await healthDataManager.savePersonalInfo(updatedInfo)
      }
  }
  ```
  ```swift
  // AIChatManager.swift:1027-1031
  Task {
      try await databaseManager.updateConversation(conversation)
      if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
          conversations[index] = conversation
      }
  ```
- **Fix**: each site needs a `do/catch` that surfaces the failure through the app's error
  presentation path, or an explicit, commented decision that the failure is ignorable.
  The fix is mechanical but must not be done as one sweeping pass — `AIChatManager:1027`
  carries a privacy consequence and should be fixed with WS-04's conclusions in hand.
- **Blast radius**: `ContentView` (10 sites) is the app's largest view file and is touched
  by WS-06; `AIChatManager` is touched by WS-03, WS-04 and WS-06. Sequence this after
  those reviewers report, or they will be reading changed code.
- **Verification**: a unit test per flow asserting the error reaches the error-presentation
  layer when the manager throws; plus the build emitting zero
  `[#NoUseUnstructuredThrowingTask]` warnings.

### WS-00-02 — The review plan's iPad build command was malformed (fixed)
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Documentation/Review/BETA-RELEASE-REVIEW-PLAN.md:48`, `Documentation/Review/prompts/FIX-AGENT-PROTOCOL.md:49`
- **Scenario**: both files specified `-destination 'platform=iPad Pro 11-inch (M5),OS=26.5'`,
  which omits `platform=iOS Simulator` and `name=`. `xcodebuild` rejects it. Every fix
  agent is instructed to run the iPad build as a verification gate, so each would have
  hit the error and either improvised a destination or reported a false failure.
  `CLAUDE.md:104` had the correct form all along; the error was introduced when the plan
  was written.
- **Fix**: **already applied** — both files now read
  `-destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5'`.
- **Verification**: the corrected command was the one Part A actually ran successfully.

---

## Baseline

### Environment

| Item | Value |
|---|---|
| Xcode | 27.1 (27A9275) |
| Swift (compiler) | 6.4 — the project builds in Swift 6 language mode |
| Simulator runtimes installed | iOS 26.5, iOS 27.0 |
| Canonical destinations | both exist (`iPhone 17 Pro`, `iPad Pro 11-inch (M5)`, OS 26.5); no substitutions made |
| Package resolution | clean |

### Builds

| Build | Result | Time | App warnings |
|---|---|---|---|
| iPhone, incremental | **BUILD SUCCEEDED** | 59 s | 14 unique sites (+4 third-party) |
| iPad, incremental | **BUILD SUCCEEDED** | 18 s | 0 — nothing recompiled, so this is not independent evidence |
| iPhone, fresh DerivedData | **BUILD SUCCEEDED** | 77 s | same 14 (+4) |

All 14 app warnings are the single `[#NoUseUnstructuredThrowingTask]` diagnostic recorded
as WS-00-01. No deprecation, unused, or Sendable warnings were emitted. The 4 third-party
warnings are mlx-swift Metal header C++17 notices and are not actionable here.

Durations are from a warm machine with populated caches and should not be quoted as
cold-build benchmarks.

### Tests

| Run | Cases | Passed | Failed | Skipped | Test time |
|---|---|---|---|---|---|
| iPhone run 1 | 258 | 258 | 0 | 0 | 56.1 s |
| iPhone run 2 | 258 | 258 | 0 | 0 | 51.5 s |
| iPad run 1 | 258 | 258 | 0 | 0 | 62.1 s |

Per-case results were diffed across all three runs: zero differences. No flakes observed —
though two runs would not catch a low-rate flake, so this is "none observed", not "none exist".

> **Correction (after WS-01).** "Unit + UI suites" overstates the coverage. Of the seven
> files in `HealthAppUITests/`, only `RegressionSmokeUITests.swift` is compiled into the
> target — the other six have a `PBXFileReference` but **zero** `in Sources` entries, so
> they are visible in Xcode's navigator and never build or run. The 258 cases are the unit
> and integration suites plus **2** UI smoke tests. See the Correction section below for
> the verified per-file counts.

### Lint

| Run | Violations | Breakdown |
|---|---|---|
| With `SwiftLintBaseline.json` | 5 | 4 `legacy_swiftui_aspect_ratio`, 1 `force_unwrapping` |
| Baseline stripped | 61 | 37 `force_unwrapping`, 20 `implicitly_unwrapped_optional`, 4 `legacy_swiftui_aspect_ratio` |

The baseline suppresses 56 violations (92%), but the distribution matters more than the
total:

| Bucket | force_unwrapping | implicitly_unwrapped_optional | legacy_swiftui_aspect_ratio |
|---|---|---|---|
| App code | **20** | 0 | 4 |
| Unit tests | 17 | 13 | 0 |
| UI tests | 0 | 7 | 0 |

All severities are `warning`; nothing fails the build. The suppressed debt is mostly test
scaffolding (`var app: XCUIApplication!`, `data(using: .utf8)!`). The 20 app-code
force-unwraps are the ones worth routing — see Leads below.

### Inventory

| Area | Files | LOC |
|---|---|---|
| App source (`HealthApp/HealthApp`) | 124 | 51,814 |
| ├ Views | 54 | 16,724 |
| ├ Services | 13 | 9,356 |
| ├ Managers | 10 | 6,170 |
| ├ Models | 14 | 6,041 |
| ├ Utils | 16 | 4,913 |
| ├ Database | 8 | 3,148 |
| ├ MLXOnDeviceLLM | 4 | 2,777 |
| ├ Networking | 2 | 444 |
| └ ViewModels | 1 | 104 |
| Unit tests | 16 | 5,142 |
| UI tests | 7 | 2,241 |
| **Total** | **147** | **59,197** |

### Plan facts: verification result

| Claim in plan §0 | Actual | Verdict |
|---|---|---|
| Database version 12 | 12 | true |
| `MARKETING_VERSION` 1.0 / `CURRENT_PROJECT_VERSION` 1 | same | true |
| iOS 26.0 target, Swift 6.0, device family "1,2" | same | true |
| Bundle ID `com.bisonhealthai.app`, icon set `AppIcon-BisonHealthAI-Pro` | same | true |
| No `PrivacyInfo.xcprivacy` | confirmed absent | true |
| No `ITSAppUsesNonExemptEncryption` | confirmed absent | true |
| Four SPM deps | confirmed; 36 pins total | true |
| `try!` 0, `fatalError` 0, `NavigationView` 0, `@unchecked Sendable` 5, `DispatchQueue` 27, `UserDefaults` 60 | same | true |
| "8 force-unwrap-ish sites" | **20 in app code** (the original figure came from a regex matching only `!.`) | **corrected in plan** |
| "~30 style rules disabled" | **27** | **corrected in plan** |
| "2 `print(`" | **0 Swift `print` calls** — both hits are a custom `PrepPrinter.print` in `AppointmentPrepDetailView.swift` | **corrected in plan** |

The plan's §0 table has been updated for all three corrections, since later workstreams
treat it as ground truth.

---

## Leads routed to other workstreams

These are not findings — they are starting points the baseline happened to expose.

| Lead | Route to |
|---|---|
| `textual` is pinned to the **`main` branch** (`5b06b81`) of the bisonbet fork, not a version. A resolve tomorrow can produce a different build of a health app. The other three deps are version-pinned. | WS-14 (already in its brief, item 8) |
| App-code force-unwraps in the database layer: `DatabaseManager.swift:978,980`, `DatabaseManager+Documents.swift:26`, `DatabaseManager+MedicalDocuments.swift:124,129` | WS-02 — **closed**: WS-02 assessed all five as safe by construction (`data(using: .utf8)!`, `sealedBox.combined!` with a default nonce, two guarded unwraps) |
| App-code force-unwraps in the import pipeline: `DocumentProcessor.swift:470,475,1536`, `BloodTestMappingService.swift:696,697,703,704`, `BloodTestResult.swift:960,978` | WS-05 |
| `SettingsManager.swift:517,536` force-unwraps, on the settings-persistence surface | WS-04 |
| `AIChatManager.swift:1027` discards the error when persisting conversation privacy preferences — same surface as prior P1-5 | WS-04 and WS-01 |
| Only 4 `DatabaseTests` cases and 3 `HealthDataManagerTests` cases cover a v12 encrypted database with 12 migrations; `RegressionSmokeUITests` has 2 | WS-15 |
| iPad build emitted no warnings only because the iPhone build had already compiled the sources — any future "iPad is clean" claim needs its own DerivedData | WS-09, WS-14 |

Full app-code lint lead list:
`/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/WS-00-app-code-forceunwrap-leads.md`

## Correction (2026-10-22, after WS-02)

This file originally described the database-layer leads as including a force-unwrapped
`db!`. That was wrong, and the error is instructive: the text came from an entry in
`SwiftLintBaseline.json`, not from current source. Today's code reads
`try db?.execute("PRAGMA foreign_keys = ON")` (`DatabaseManager.swift:172`) and there is
no `db!` anywhere in the app. The baseline file holds 95 entries against 61 live
violations, so **its entries are a historical record, not evidence of current code** —
any reviewer quoting it must re-read the cited line in source first. WS-02 caught this.

### 113 UI test functions never compile (WS-01 caught this; verified here)

This file originally reported "unit + UI suites, 258 cases, all passing", which gave the
UI layer a clean bill of health it has not earned. Verified by inspecting
`project.pbxproj` for `in Sources` membership and by listing the suites that actually
executed in the iPhone run:

| File | Target membership | Test funcs |
|---|---|---|
| `RegressionSmokeUITests.swift` | **compiled** | 2 |
| `AccessibilityUITests.swift` | orphaned | 10 |
| `BloodTestEntryUITests.swift` | orphaned | 19 |
| `ChatInterfaceUITests.swift` | orphaned | 19 |
| `DocumentManagementUITests.swift` | orphaned | 28 |
| `HealthAppUITests.swift` | orphaned | 17 |
| `PersonalInfoEditorUITests.swift` | orphaned | 20 |
| | | **113 orphaned** |

Every file in `HealthAppTests/` (the unit target) *is* compiled — the problem is confined
to the UI target. The executed-suite list from the test results confirms it:
`RegressionSmokeUITests` is the only UI suite present among the 20 suites that ran.

Consequences beyond the miscount: `AccessibilityUITests.swift` is one of the orphaned
files, so WS-10 must not treat it as working coverage; and because the orphaned files have
not been compiled in some time, they contain stale selectors and strings that will fail
when re-added. Re-enabling them is therefore real work, not a checkbox. Routed to WS-15 as
its highest-priority item and recorded in the tracker.

## Readiness snapshot

Nothing blocks the other workstreams: the project builds, the suite is green and
non-flaky, and package resolution works. Reviewers should not be alarmed by the 56
baseline-suppressed lint violations — they are overwhelmingly test scaffolding, and the
20 app-code sites are enumerated above rather than left to be rediscovered. The one thing
that should not be dismissed is WS-00-01: the compiler has already identified 14 places
where a thrown error is dropped on a save or delete path, and at least one of them sits on
the privacy-preference surface that the previous review flagged as P1.

## Machine-readable summary
```json
[
  {"id":"WS-00-01","title":"14 discarded error paths on user-data save and delete flows (unused throwing Task)","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/ContentView.swift:322","HealthApp/HealthApp/ContentView.swift:1440","HealthApp/HealthApp/ContentView.swift:1446","HealthApp/HealthApp/Views/VitalsListView.swift:34","HealthApp/HealthApp/Views/VitalsListView.swift:49","HealthApp/HealthApp/Views/ChatDetailView.swift:148","HealthApp/HealthApp/Managers/AIChatManager.swift:1027"],"effort":"M","area":"baseline"},
  {"id":"WS-00-02","title":"Review plan's iPad build destination was malformed (fixed)","severity":"P2","confidence":"CONFIRMED","files":["Documentation/Review/BETA-RELEASE-REVIEW-PLAN.md:48","Documentation/Review/prompts/FIX-AGENT-PROTOCOL.md:49"],"effort":"S","area":"baseline"}
]
```
