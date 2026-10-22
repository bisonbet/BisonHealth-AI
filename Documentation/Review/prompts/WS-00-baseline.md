# WS-00 — Baseline: build, test, lint, inventory

**Phase 0 · model tier: cheap · must complete before Phases 1–3 · output:
`Documentation/Review/findings/WS-00-baseline.md`**

You are establishing the ground truth every other reviewer will rely on. You are not
looking for bugs. You are recording what the repo does *right now*, so that later
findings can be separated from pre-existing noise.

## Do this, in order

1. Record `git rev-parse --short HEAD`, `git status --porcelain`, and `git log -5 --oneline`.
2. Build for iPhone and for iPad using the canonical commands in §0 of the plan. Capture
   the full warning list for each. Save warnings to
   `Documentation/Review/findings/WS-00-warnings.txt` and count them by category
   (deprecation, concurrency, unused, Sendable, other).
3. Run the unit + UI test suites on iPhone. Record: total tests, passed, failed, skipped,
   wall-clock duration, and the name of every failure. Then run the suite a **second**
   time and list any test whose result changed — those are flaky and matter more than
   the failures.
4. Run the iPad suite the same way (single run is fine).
5. Run SwiftLint twice: once normally (baseline applied) and once with the baseline
   bypassed, so the suppressed debt is visible. Report violation counts by rule for both,
   and the ten files with the most suppressed violations.
6. Inventory: per-directory Swift file count and LOC under `HealthApp/HealthApp/`;
   the twenty largest files; the list of test files with LOC.
7. Confirm the declared project facts in plan §0 are still true. Specifically check:
   `currentDatabaseVersion` in `HealthApp/HealthApp/Database/DatabaseManager.swift`,
   `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `IPHONEOS_DEPLOYMENT_TARGET`,
   `ASSETCATALOG_COMPILER_APPICON_NAME`, and whether a `PrivacyInfo.xcprivacy` exists.
   Report any mismatch with the plan — the plan may be stale, and other agents will
   trust it unless you correct it.
8. Record the simulator runtimes actually installed (`xcrun simctl list runtimes`) and
   whether the destinations in the canonical commands exist on this machine. If they
   don't, say which destination you substituted.

## Output

Use the output contract from plan §1.6, with one deviation: your "Findings" section
holds only things that *block other reviewers* (e.g. "the project does not build",
"tests cannot run without a provisioning profile"). Everything else goes in a
**Baseline** section of plain tables.

End with a short **Readiness snapshot**: does it build, do tests pass, how much lint debt
is hidden, and what a reviewer should not be alarmed by because it is pre-existing.
