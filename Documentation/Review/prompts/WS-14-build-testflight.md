# WS-14 — Build, signing & TestFlight pipeline

**Phase 3 · model tier: mid · output: `Documentation/Review/findings/WS-14-build-testflight.md`**

Today there is no CI, no fastlane, no test plan, one shared scheme, and
`CURRENT_PROJECT_VERSION = 1`. Shipping repeated TestFlight builds by hand from Xcode
works until it doesn't; this workstream makes the release path repeatable and documents it.

## Audit

1. **Scheme and configurations.** `HealthApp.xcscheme` is the only shared scheme. Record
   which build configurations exist, what differs between Debug and Release, whether tests
   are wired into the scheme's Test action, and whether Release has anything Debug-only
   left enabled (verbose logging in particular — coordinate with WS-07).
2. **Signing.** `CODE_SIGN_STYLE = Automatic`, team `4W55VW7UXX`. Determine what an
   archive requires that a simulator build does not: a distribution certificate, a
   provisioning profile covering HealthKit and the increased-memory-limit entitlement, and
   an App Store Connect app record for `com.bisonhealthai.app`. Report which of these you
   can verify and which need the human's account access.
3. **Entitlement drift.** `aps-environment = development` in a distribution build is a
   mismatch. List every entitlement and its correct production value (coordinate with
   WS-13 item 4).
4. **Version strategy.** `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1`.
   TestFlight rejects a duplicate build number. Propose the scheme (e.g. build number from
   CI run number or commit count — `git rev-list --count HEAD` is 560 today, which is a
   usable monotonic source) and where it should be set so it is not forgotten.
5. **Archive validation.** Produce the exact command sequence for a clean archive and
   export, and run as much of it as is possible without distribution credentials:

```bash
cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/BisonHealth.xcarchive clean archive
```

   Record every error and warning. A generic-iOS Release archive surfaces problems a
   simulator build never shows (missing arm64 slices, bitcode/symbol issues, asset
   catalogue errors, entitlement mismatches). If it fails for credential reasons, say so
   precisely and report everything that failed *before* that point.
6. **dSYMs and symbolication.** Confirm Release produces dSYMs, and define where they are
   kept so a beta crash report can be symbolicated later.
7. **Test plan.** There is no `.xctestplan`. Propose one (or two: a fast PR plan and a
   full pre-release plan), naming which of the 23 test files go in each and which need
   a simulator with specific settings.
8. **Dependency pinning.** Read
   `HealthApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. For
   each of the four dependencies: pinned revision, whether the requirement is a branch or
   a version range, and the risk that a resolve produces a different build tomorrow. A
   branch-tracked dependency in a health app is a reproducibility problem — flag it.
   `bisonbet/textual` is a fork: note who maintains it and what happens if upstream moves.
9. **Build reproducibility.** Can a clean checkout on another machine build without manual
   steps? List every manual step (simulator runtimes, Xcode version, package resolution,
   signing). Record the Xcode and Swift versions this audit used.

## Deliverable: the release runbook

Write a runbook, concrete enough that a competent agent or a tired human can follow it at
2am, covering:
- preflight (clean checkout, package resolve, lint, both builds, full test plan);
- version/build bump;
- archive, validate, upload;
- App Store Connect steps: export compliance, what's-new, beta app review notes, tester
  groups;
- post-upload verification: install from TestFlight on a real device, run the smoke flow,
  check the crash-free launch;
- rollback: what to do when a bad build reaches testers.

Also propose a minimal CI configuration (a GitHub Actions workflow on macOS running lint +
both builds + the fast test plan on PRs), as a file body in your report. Do not create it;
that is a Phase 5 fix.

## Output

Plan §1.6 contract, plus the **release runbook** and the **proposed CI workflow** and
**proposed test plan** as fenced blocks. Note clearly which steps you could not execute
for lack of credentials or hardware.
