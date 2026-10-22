# BisonHealth AI — Beta & App Store Readiness Review Plan

**Created**: 2026-10-22
**Baseline commit**: `84e8c0f7` (branch `main`)
**Goal**: take the app from "works on my machine" to (a) a TestFlight build safe to hand to outside beta testers, and (b) an App Store submission that survives review.

This document is the **orchestration contract**. It is written so that a mix of strong
and weak agents can execute it with no additional context: every workstream has a
standalone prompt file under `Documentation/Review/prompts/`, a fixed output location,
and verification rules that make it hard to produce noise.

---

## 0. Repo facts the agents should not have to rediscover

| Fact | Value |
|---|---|
| App source | `HealthApp/HealthApp/` — 124 Swift files, ~51,800 LOC |
| Tests | `HealthApp/HealthAppTests/` + `HealthAppUITests/` — 23 files, ~7,400 LOC |
| Xcode project | `HealthApp/HealthApp.xcodeproj` (single shared scheme `HealthApp`, no test plan) |
| Language mode | Swift 6.0, strict concurrency |
| Deployment target | iOS 26.0, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad) |
| Bundle ID | `com.bisonhealthai.app`, team `4W55VW7UXX`, automatic signing |
| Version / build | `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` |
| App icon set | `AppIcon-BisonHealthAI-Pro` (second set `AppIcon-Doctor-Dark` is unused by build settings) |
| Database | SQLite + CryptoKit, `currentDatabaseVersion = 12` |
| SPM deps | `aws-sdk-swift`, `stephencelis/SQLite.swift`, `ml-explore/mlx-swift-lm`, `bisonbet/textual` |
| Entitlements | HealthKit, `kernel.increased-memory-limit`, `aps-environment = development` |
| Info.plist | only `NSAppTransportSecurity.NSAllowsLocalNetworking`; rest generated from `INFOPLIST_KEY_*` |
| Privacy manifest | **absent** (no `PrivacyInfo.xcprivacy` anywhere in the project) |
| CI | **none** (no `.github/`, no fastlane, no xcodebuild automation) |
| Lint | SwiftLint present, `baseline: SwiftLintBaseline.json` (47 KB) suppresses pre-existing debt; ~30 style rules disabled |
| Prior review | `PRE-BETA-REVIEW.md` — 2 P0, 15 P1, ~40 P2 findings, marked fixed 2026-08-30, plus a fresh-eyes round |
| Hygiene snapshot | 0 `try!`, 0 `fatalError`, 0 `NavigationView`, 2 `print(`, 2 TODO/FIXME, 8 force-unwrap-ish sites, 5 `@unchecked Sendable`, 27 `DispatchQueue` uses, 60 `UserDefaults` uses |

### Canonical commands

```bash
# iPhone build
cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

```bash
# iPad build
cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iPad Pro 11-inch (M5),OS=26.5' build
```

```bash
# Unit + UI tests (iPhone)
cd HealthApp && xcodebuild test -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

```bash
# Lint, including the debt the baseline hides
cd HealthApp && swiftlint lint --config .swiftlint.yml && swiftlint lint --no-cache --config .swiftlint.yml --reporter json > /tmp/lint-all.json
```

---

## 1. Rules of engagement (every agent reads this section)

### 1.1 Review phases are read-only

During Phases 0–3 agents **must not**: edit source, run `git commit`, `git checkout`,
`git stash`, create branches, reformat code, add files to `project.pbxproj`, or install
tooling that changes the repo. The only writes allowed are the agent's own output file
under `Documentation/Review/findings/`. Fixing happens in Phase 5, under a different
protocol.

### 1.2 Evidence requirements — no finding without proof

A finding is only valid if it carries all of:

1. **Location** — `path/to/File.swift:123` (verified to exist; cite the line you actually read).
2. **Evidence** — the relevant code, quoted, 15 lines or fewer.
3. **Failure scenario** — concrete inputs or state → the wrong behaviour. "Could be
   fragile" is not a scenario. "User imports a 2-page PDF whose second page fails to
   render → `pages[1]` force-indexed → crash" is.
4. **Confidence** — `CONFIRMED` (you traced the whole path, or reproduced it) or
   `PLAUSIBLE` (you believe it but one link is unverified; say which link).
5. **Severity** — per the rubric in §1.3.
6. **Fix sketch** — one or two sentences. If you don't know the fix, write
   `fix: unknown — needs design`. Never invent an API. If you are unsure an API exists,
   verify with `grep` in the repo or with the Context7/Ref docs tools.
7. **Blast radius** — what else touches this code, so triage can sequence it.

### 1.3 Severity rubric (tie to *this* release, not abstract quality)

| Severity | Definition |
|---|---|
| **P0** | Beta-blocker. Data loss or corruption, PHI leaving the device or landing in plaintext/logs, crash on a path a normal tester will hit, app unusable after upgrade, or a certain App Store rejection. |
| **P1** | Must fix before widening the beta. Core flow broken but with a workaround, PHI exposed only via unusual steps, a likely (not certain) rejection risk, or a migration that degrades data. |
| **P2** | Fix before public release. Wrong-but-recoverable behaviour, poor failure UX, iPad/accessibility gaps, perf problems on older hardware. |
| **P3** | Post-launch. Polish, refactors, test debt, nice-to-haves. |

A reviewer who reports everything as P0 has produced nothing. Expect most findings at
P2. If a workstream yields no P0/P1, that is a legitimate and useful result — say so
explicitly rather than inflating something.

### 1.4 Out of scope for all reviewers

- Style, formatting, naming, line length, file length — SwiftLint owns these.
- Anything listed as deliberately deferred in `PRE-BETA-REVIEW.md` (§"Deliberately
  deferred", marked with `ponytail:` comments at the call sites). Re-report one of these
  **only** if you can show it is worse than documented.
- HIPAA compliance as a goal. The app ships as "personal use, not HIPAA compliant"
  (`README.md`). Review for *privacy correctness and honest claims*, not for BAA-grade compliance.
- Proposing a rewrite. Findings are defects, not architecture opinions. Architecture
  concerns go in a single "structural risks" section at the end of your report, capped at
  five bullets.

### 1.5 Finding caps and ranking

Each workstream reports **at most 15 findings**, ranked most severe first. If you found
more, report the top 15 and add a one-line count of what you dropped. This forces
triage at the source instead of handing a human 400 undifferentiated bullets.

### 1.6 Output contract

Write exactly one file: `Documentation/Review/findings/WS-NN-<slug>.md`, with this shape:

```markdown
# WS-NN — <Workstream name>

- **Agent / model**: <who ran this>
- **Date**: YYYY-MM-DD
- **Commit reviewed**: <git rev-parse --short HEAD>
- **Scope actually covered**: <files/areas you really read>
- **Scope not covered**: <what you skipped and why>
- **Verdict**: <one sentence: is this area beta-ready?>
- **Counts**: P0=n P1=n P2=n P3=n (dropped: n)

## Findings

### WS-NN-01 — <short title>
- **Severity**: P1 · **Confidence**: CONFIRMED · **Effort**: S|M|L
- **Location**: `path:line`
- **Scenario**: ...
- **Evidence**:
  ```swift
  ...
  ```
- **Fix**: ...
- **Blast radius**: ...
- **Verification**: how a fixer proves it is fixed (test to write, steps to repro)

## Structural risks (max 5 bullets)

## Machine-readable summary
```json
[
  {"id":"WS-NN-01","title":"...","severity":"P1","confidence":"CONFIRMED",
   "files":["path:line"],"effort":"S","area":"<workstream slug>"}
]
```
```

The JSON block is what the triage agent merges; it is not optional.

### 1.7 When you are blocked

If you cannot build, cannot find a referenced file, or the scope prompt contradicts the
repo, stop and write the output file with `Verdict: BLOCKED` and the reason. Do not
guess your way through, and do not silently narrow the scope.

---

## 2. Workstreams

Phases 1–3 are read-only and have **no dependencies on each other** — run as many in
parallel as your budget allows. Only Phase 0 must finish first, and only Phase 4 must
run last.

| WS | Name | Phase | Model tier | Prompt |
|---|---|---|---|---|
| 00 | Baseline: build, test, lint, inventory | 0 | cheap | `prompts/WS-00-baseline.md` |
| 01 | Prior-findings regression verification | 1 | strong | `prompts/WS-01-prior-findings.md` |
| 02 | Data integrity, migrations, encryption at rest | 1 | strong | `prompts/WS-02-data-integrity.md` |
| 03 | Swift 6 concurrency & actor isolation | 1 | strong | `prompts/WS-03-concurrency.md` |
| 04 | AI provider layer & network robustness | 1 | strong | `prompts/WS-04-ai-providers.md` |
| 05 | Document import & extraction pipeline | 1 | strong | `prompts/WS-05-document-pipeline.md` |
| 06 | SwiftUI state, lifecycle & memory | 1 | strong | `prompts/WS-06-swiftui-state.md` |
| 07 | PHI handling & security | 1 | strong | `prompts/WS-07-phi-security.md` |
| 08 | Error handling & failure UX | 1 | mid | `prompts/WS-08-error-ux.md` |
| 09 | iPad & adaptive layout | 2 | mid | `prompts/WS-09-ipad-adaptive.md` |
| 10 | Accessibility | 2 | cheap | `prompts/WS-10-accessibility.md` |
| 11 | Performance, memory & battery | 2 | mid | `prompts/WS-11-performance.md` |
| 12 | On-device model lifecycle (MLX) | 2 | mid | `prompts/WS-12-mlx-lifecycle.md` |
| 13 | App Store compliance & metadata | 3 | mid | `prompts/WS-13-appstore-compliance.md` |
| 14 | Build, signing & TestFlight pipeline | 3 | mid | `prompts/WS-14-build-testflight.md` |
| 15 | Test suite quality & coverage gaps | 3 | mid | `prompts/WS-15-test-coverage.md` |
| 16 | Docs & plan drift | 3 | cheap | `prompts/WS-16-docs-drift.md` |
| 17 | Triage, dedupe & fix sequencing | 4 | strong | `prompts/WS-17-triage.md` |

**Model tiering.** "cheap" workstreams are checklist- and grep-driven: a small model
can do them if it follows the prompt literally. "strong" workstreams require tracing
async control flow across files and holding several files in mind at once; a weak model
will produce confident nonsense there. "mid" sits between: structured, but needs
judgment about user impact.

### Suggested dispatch batches

```
Batch A (after WS-00):   WS-01, WS-02, WS-03, WS-07      ← correctness/safety core
Batch B:                 WS-04, WS-05, WS-06, WS-08
Batch C:                 WS-09, WS-10, WS-11, WS-12
Batch D:                 WS-13, WS-14, WS-15, WS-16
Then:                    WS-17 (needs every findings file present)
```

Batches exist for cost control and for your own ability to read the results, not
because of technical dependencies. Reorder freely; put Batch D first if the App Store
timeline is the binding constraint.

---

## 3. Phase 5 — fix execution protocol

Review output is not a licence to refactor. Fixes run under these rules:

1. **One finding per change.** Branch name `fix/ws-NN-NN-<slug>`. A fix that touches a
   second finding's code must say so and stop for a decision.
2. **File ownership.** Only one fix agent may hold a file at a time. The triage agent
   (WS-17) publishes a fix order with an ownership map; respect it. Two agents editing
   `DocumentProcessor.swift` concurrently will clobber each other — there is no merge
   referee in this workflow.
3. **Schema changes.** Any schema change increments `currentDatabaseVersion` *and* adds
   a migration case *and* is tested fresh-install + upgrade-from-12. No exceptions —
   see `CLAUDE.md` §"Database Migrations".
4. **New files** must be registered in `project.pbxproj` by hand (four places; see
   `AGENTS.md` §"Adding New Files to Xcode Project"). Expect SourceKit noise until the
   next build.
5. **Verification gate.** Before claiming done: the finding's stated verification step
   passes, iPhone and iPad builds succeed, focused tests pass, `swiftlint lint` is clean,
   and `git diff` has been read end to end. Report the actual command output, not a
   summary of it.
6. **Definition of Done** from `CLAUDE.md` applies: remove code this change made unused,
   no commented-out blocks, merge newly duplicated helpers, no secrets or PHI in source,
   tests, fixtures, or logs.
7. **No opportunistic edits.** If you see something else broken, add it to
   `Documentation/Review/TRACKER.md` as a new finding. Don't fix it in this change.

---

## 4. Exit criteria

### Gate A — safe to hand to outside beta testers
- [ ] Zero open P0 findings; every P1 either fixed or explicitly accepted in writing with a reason.
- [ ] Fresh install works on iPhone and iPad; upgrade from a v12 database preserves all data.
- [ ] Unit + UI suites green on both device families, run twice to catch flakes.
- [ ] No PHI in any log, export, crash report, or share-sheet payload (WS-07 signs off).
- [ ] First-launch disclaimer, Terms, and Privacy Policy are reachable and accurate about what leaves the device.
- [ ] Every AI provider path (MLX on-device, Bedrock, OpenAI-compatible) either works or fails with a message a non-engineer can act on.
- [ ] A tester can report a problem: feedback channel documented, and enough diagnostics exist to debug a report without PHI.
- [ ] Build/version numbering ready for repeated TestFlight uploads (WS-14).

### Gate B — ready to submit to App Store review
- [ ] Gate A met, plus zero open P1.
- [ ] `PrivacyInfo.xcprivacy` present and accurate; App Privacy answers in App Store Connect match the code.
- [ ] Export-compliance declaration settled (the app uses CryptoKit and TLS; the key is currently absent from `Info.plist`).
- [ ] HealthKit usage justified in review notes; usage strings match actual behaviour.
- [ ] Medical-disclaimer placement reviewed against the current App Review Guidelines (health/medical sections).
- [ ] On-device model download reviewed against the current guidelines on downloaded content/code.
- [ ] Icon, screenshots, age rating, support/marketing/privacy URLs, and reviewer demo path all present.
- [ ] Archive from a clean checkout, uploaded, and installed from TestFlight on a real device — not just a simulator.

---

## 5. Where things live

```
Documentation/Review/
├── BETA-RELEASE-REVIEW-PLAN.md     ← this file
├── TRACKER.md                      ← merged finding list, hand-maintained + WS-17 output
├── prompts/WS-NN-*.md              ← standalone agent briefs (copy-paste or point an agent at the path)
└── findings/WS-NN-*.md             ← agent output, one file per workstream
```

Dispatching a workstream to an agent is one line:

> Read `Documentation/Review/BETA-RELEASE-REVIEW-PLAN.md` sections 0 and 1, then execute
> `Documentation/Review/prompts/WS-03-concurrency.md` exactly. Write your output to the
> path that prompt specifies and nothing else.
