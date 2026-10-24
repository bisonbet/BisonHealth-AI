# WS-14 — Build, signing & TestFlight pipeline

- **Agent / model**: Claude (Sonnet 5.5), read-only review
- **Date**: 2026-10-24
- **Commit reviewed**: f95cf804 (tree clean before and after; all build output went to a scratchpad DerivedData)
- **Scope actually covered**: `project.pbxproj` build settings for all 4 targets x 2 configurations; the shared scheme; `HealthApp.entitlements`; `Info.plist`; `Package.resolved` and the 4 SPM requirements; the asset catalog app icon; `#if DEBUG` / `AppTestRuntime` test hooks; local provisioning profiles for `com.bisonhealthai.app` (read-only decode); local codesigning identities.
  **Builds I actually ran** (Xcode 27.1 / 27A9275, Swift 6.4 compiler in Swift 6.0 language mode, macOS 27.0.1, arm64):
  1. `generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build` -> **BUILD SUCCEEDED**. This typechecks `MLXOnDeviceLLM/`. 10 warning lines, 3 unique first-party (see WS-14-09).
  2. `generic/platform=iOS -configuration Release CODE_SIGNING_ALLOWED=NO clean archive` -> **ARCHIVE SUCCEEDED**, same 3 first-party warnings, no errors. The archive is arm64-only, 46 MB, and its dSYM UUID matches the binary (`E0C6D5D7-5A3A-3063-89EB-E5E3D7F33A91`).
  3. `xcodebuild -showBuildSettings` for Release and Debug (strict-concurrency and optimisation settings).
- **Scope not covered**:
  - **No signed archive and no export.** `CODE_SIGNING_ALLOWED=NO` produces an unsigned bundle (`codesign: code object is not signed at all`), so entitlements are not embedded and I could not observe an entitlement/profile mismatch.
  - `altool --validate-app` / upload (needs account credentials).
  - Whether an App Store Connect app record, a distribution certificate, or any prior TestFlight build exists.
  - Whether Xcode 27.1 on this machine is a release or a beta (ASC refuses beta-SDK uploads). `CFBundleShortVersionString` is `27.1` with no "beta" marker, but I could not prove it.
  - A true clean-checkout build on a second machine, and a CI run.
  - Any simulator or test execution (explicitly forbidden for this run). I did not run tests; the 293-test figure is the caller's.
- **Verdict**: The Release configuration archives cleanly and has no Debug-only leakage, but the release path has never been made repeatable: the build number is a hard-coded `1`, the export-compliance key and an app-level privacy manifest are missing, one dependency tracks a moving branch, and no automation or test plan exists, so it is **not ready for repeated TestFlight uploads until WS-14-01..03 are fixed**; none of it blocks the code itself.
- **Counts**: P0=0 P1=3 P2=6 P3=2 (dropped: 0)

No P0. Things I specifically checked and found clean are listed under "Verified clean" so a fixer does not redo them.

## Findings

### WS-14-01 — `CURRENT_PROJECT_VERSION = 1` is hard-coded in 8 places; a second upload of 1.0 will collide
- **Severity**: P1 · **Confidence**: PLAUSIBLE (settings and built `CFBundleVersion=1` CONFIRMED; the unverified link is App Store Connect's rejection of a repeated build number, which is documented Apple behaviour that I did not exercise because I cannot upload) · **Effort**: S
- **Location**: `HealthApp/HealthApp.xcodeproj/project.pbxproj:1089` (app Debug), `:1131` (app Release), plus `:1171 :1192 :1212 :1232` for the test targets
- **Scenario**: Tester builds are uploaded one after another from the same `MARKETING_VERSION = 1.0`. Build 2 is archived without anyone remembering to edit the number in two Xcode panes, and ASC rejects it as a duplicate (or, if Xcode's export option `manageAppVersionAndBuildNumber` silently rewrites it, the number in the archive no longer matches the binary you tested). There is no `.xcconfig`, no `VERSIONING_SYSTEM = apple-generic` (so `agvtool new-version` does nothing useful), no script phase, no CI.
- **Evidence**:
  ```
  CODE_SIGN_STYLE = Automatic;
  CURRENT_PROJECT_VERSION = 1;          # project.pbxproj:1131 (Release), identical at :1089
  ...
  MARKETING_VERSION = 1.0;              # :1153
  # archive Info.plist (observed): CFBundleVersion = 1, CFBundleShortVersionString = 1.0
  ```
- **Fix**: Never edit the number by hand. Pass it on the archive command line from a monotonic source: `CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)` (583 today). That overrides all targets. Requirements for that to stay monotonic: archive from `main` with a full-depth clone (CI needs `fetch-depth: 0`; the repo is not shallow here), and never rewrite/squash published history. Add the number to the runbook preflight and print it before upload. Bump `MARKETING_VERSION` only for a new train.
- **Blast radius**: Only the release procedure. Test targets carry the same literal; harmless.
- **Verification**: `xcodebuild archive ... CURRENT_PROJECT_VERSION=999` then `plutil -p <archive>/Products/Applications/HealthApp.app/Info.plist | grep CFBundleVersion` shows 999.

### WS-14-02 — `ITSAppUsesNonExemptEncryption` is absent from the built Info.plist
- **Severity**: P1 · **Confidence**: CONFIRMED that the key is absent from the shipped plist; the consequence (a "Missing Compliance" hold on every uploaded build until answered in ASC) is Apple's documented behaviour, not exercised · **Effort**: S
- **Location**: `project.pbxproj:1094-1105` (INFOPLIST_KEY list) and `HealthApp/HealthApp/Info.plist`
- **Scenario**: Every TestFlight upload stops at "Missing Compliance" and cannot be given to external testers until someone answers the encryption questionnaire in the ASC web UI, for every build. The app does use encryption (CryptoKit AES at rest, TLS to Bedrock/OpenAI-compatible servers), so the correct answer needs a deliberate decision (WS-13 owns it).
- **Evidence**: built `HealthApp.app/Info.plist` (decoded with `plutil -p` from the Release archive) contains `LSApplicationCategoryType`, `MinimumOSVersion`, `NSAppTransportSecurity`, the four usage strings and `UIRequiredDeviceCapabilities`, and no `ITSAppUsesNonExemptEncryption`. The build settings list has no `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption`.
- **Fix**: Once WS-13 decides the value, add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` (or `YES` with the proper declaration) to both app configurations, so it is in the binary and not a per-build manual step.
- **Blast radius**: Info.plist only. Also check whether App Store review requires documentation if the answer is YES.
- **Verification**: rebuild the archive, `plutil -p ... | grep ITSAppUses`; upload shows no "Missing Compliance" status.

### WS-14-03 — No app-level privacy manifest while the app calls required-reason APIs
- **Severity**: P1 (WS-13 may rate it higher; it is also on the plan as a certain-rejection candidate) · **Confidence**: PLAUSIBLE (absence and API use CONFIRMED; the unverified link is whether ASC currently hard-rejects or only emails, which I could not test without an upload) · **Effort**: S
- **Location**: no `PrivacyInfo.xcprivacy` at all in the repo; API use at `HealthApp/HealthApp/HealthAppApp.swift:289`, `Managers/AppLog.swift:679`
- **Scenario**: The first upload is flagged ITMS-91053 (missing API declaration) for `UserDefaults` and file-timestamp APIs. Archive inspection: the only `PrivacyInfo.xcprivacy` in `HealthApp.app` is inside `aws-sdk-swift_AWSClientRuntime.bundle`; none for the app itself, SQLite.swift, Textual, or MLX.
- **Evidence**:
  ```swift
  // HealthAppApp.swift:289
  if let lastSync = UserDefaults.standard.object(forKey: "healthKitLastSyncDate") as? Date {
  // AppLog.swift:679
  includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
  ```
- **Fix**: Add `PrivacyInfo.xcprivacy` to the app target (register it in `project.pbxproj`, 4 places per the repo's memory note) declaring UserDefaults (CA92.1) and file timestamp (C617.1 or 3B52.1, whichever matches the use), plus `NSPrivacyCollectedDataTypes` consistent with the Privacy Policy claims. Then run Xcode's "Generate Privacy Report" on the archive.
- **Blast radius**: App Store submission and the privacy label; coordinate with WS-13.
- **Verification**: find the manifest in the new archive's `.app`; Xcode privacy report lists no undeclared API.

### WS-14-04 — `textual` tracks the fork's `main` branch; the fork is already 34 commits past the pin
- **Severity**: P2 · **Confidence**: CONFIRMED (checked with `git ls-remote` and a fetch of the fork) · **Effort**: S
- **Location**: `project.pbxproj:1300-1304`; `Package.resolved:311-317`
- **Scenario**: A clean checkout is currently reproducible because `Package.resolved` is tracked (pin `5b06b811`). But the declared requirement is a branch, so *File > Packages > Update to Latest*, deleting `Package.resolved`, or a CI job without `-onlyUsePackageVersionsFromResolvedFile` moves the health app's Markdown renderer to `ad589638` (34 newer commits, including a new Mermaid renderer) with no review. Textual draws chat output, which is PHI-adjacent.
- **Evidence**:
  ```
  repositoryURL = "https://github.com/bisonbet/textual";
  requirement = { branch = main; kind = branch; };
  // Package.resolved
  "branch": "main", "revision": "5b06b811c0f5313b6b84bbef98c635a630638c38"
  // remote HEAD today: ad589638b23e80557aaf2fa959760feac643a1e1
  ```
  The GitHub API reports the repo as a fork of `gonzalezreal/textual`. Pinned HEAD message: "Use safe resource bundle lookup for Prism (#21)". Whether `bisonbet` is the project owner I could not verify.
- **Fix**: Switch the requirement to an exact revision (or tag the fork and use `exactVersion`), and keep the fork's pinned commit reachable. Record what the fork changes relative to upstream.
- **Blast radius**: One package; indirect `swift-concurrency-extras` and `swiftui-math`.
- **Verification**: the pbxproj requirement `kind` is `revision` or `exactVersion`; a fresh resolve in an empty DerivedData gives the same revision.

### WS-14-05 — No automated gate: no CI, no test plan, and nothing ever runs Release or the device-only code
- **Severity**: P2 · **Confidence**: CONFIRMED (repo contents and scheme) · **Effort**: M
- **Location**: `HealthApp.xcodeproj/xcshareddata/xcschemes/HealthApp.xcscheme` (TestAction, `buildConfiguration = "Debug"`); no `.github/`, `fastlane/`, `*.xctestplan`, `ExportOptions*.plist` tracked
- **Scenario**: A change compiled only on the simulator ships with an error in `MLXOnDeviceLLM/` (both files are `#if !targetEnvironment(simulator)`); or breaks only the Release config where ~40 `#if DEBUG` sites are removed. Today the only protection is a person remembering to run the generic-iOS build. The "gate" `xcodebuild test` runs 293 unit tests plus the single UI test file that is actually a target member (`RegressionSmokeUITests`, 2 tests); the 113 other UI tests (tracker item 25, known, deferred) compile nowhere. Testing is Debug-only; Release has `ENABLE_TESTABILITY = NO`, so `@testable` tests cannot run against it.
- **Evidence**:
  ```xml
  <TestAction buildConfiguration = "Debug" ... shouldAutocreateTestPlan = "YES">
  ```
  Release archive and device Debug build both succeeded in this review (see Scope), which shows the *current* state is fine, not that anything enforces it.
- **Fix**: Adopt the proposed test plan and CI workflow below; make `generic/platform=iOS` Debug build and a Release archive (unsigned) mandatory CI steps.
- **Blast radius**: Process only.
- **Verification**: a PR that introduces a type error inside the MLX `#if` block turns CI red.

### WS-14-06 — Signed archive and export path is unproven and not written down
- **Severity**: P2 · **Confidence**: PLAUSIBLE (what exists locally is CONFIRMED; whether a signed export succeeds and whether an ASC record exists could not be tested without credentials) · **Effort**: S
- **Location**: `project.pbxproj:1088` (`CODE_SIGN_STYLE = Automatic`), `:994` (`DEVELOPMENT_TEAM = 4W55VW7UXX`)
- **Scenario**: At 2am the archive step fails with "No signing certificate 'Apple Distribution' found" or the upload fails because no ASC record exists for `com.bisonhealthai.app`.
- **What I verified locally (read-only)**:
  - Keychain code-signing identities: exactly one, `Apple Development: Timothy Champ`. **No Apple Distribution identity is present.** Automatic signing with a cloud-managed distribution certificate may cover this; I could not test it.
  - `~/Library/Developer/Xcode/UserData/Provisioning Profiles` contains `iOS Team Store Provisioning Profile: com.bisonhealthai.app` (expires 2027-06-08): `get-task-allow = false`, `aps-environment = production`, `beta-reports-active = true`, HealthKit, `kernel.increased-memory-limit`, `healthkit.background-delivery`. This is a distribution profile for the right bundle ID with every capability the app requests, which suggests a store export was attempted from this machine before. It does not prove an ASC app record exists.
  - A development profile `iOS Team Provisioning Profile: com.bisonhealthai.app` (expires 2027-06-16) with `aps-environment = development`.
- **Needs the human**: an Apple Distribution certificate (or automatic cloud signing enabled), an ASC app record + at least one build, the TestFlight tester groups, and `-allowProvisioningUpdates` authentication on the archiving machine.
- **Fix**: Check in an `ExportOptions.plist` (below) and run the signed archive once before the first real beta so failures show up before the deadline.
- **Blast radius**: Release procedure only.
- **Verification**: `xcodebuild -exportArchive` produces an `.ipa`; `altool --validate-app` returns no errors.

### WS-14-07 — App Store icon is stored with an alpha channel
- **Severity**: P2 · **Confidence**: PLAUSIBLE (the file is RGBA; every pixel is fully opaque, minimum alpha = 255, and the compiled `Assets.car` rendition reports `Opaque: True`; but its `Encoding` is `ARGB`, and I could not run ASC validation to see whether it objects) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Assets.xcassets/AppIcon-BisonHealthAI-Pro.appiconset/AppIcon-BisonHealthAI-Pro-1024.png`
- **Scenario**: Upload fails or warns with ITMS-90717 ("can't be transparent nor contain an alpha channel"). Apple has historically checked for the channel, not for transparent pixels.
- **Evidence**: `file`: `PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced`. All other sizes are also RGBA (same harmless caveat).
- **Fix**: Re-export the 1024 marketing icon as RGB (no alpha), e.g. flatten in Preview/ImageMagick `-alpha off`. Do not edit the asset until after the review phases.
- **Blast radius**: Asset only. The second set `AppIcon-Doctor-Dark` is compiled out (not referenced by build settings) and untouched.
- **Verification**: `file` shows `8-bit/color RGB`; validation passes.

### WS-14-08 — Build toolchain prerequisites are not recorded, and one is a hidden manual download
- **Severity**: P2 · **Confidence**: PLAUSIBLE (observed what this machine has; I did not build on a machine without these) · **Effort**: S
- **Location**: `CLAUDE.md` build commands; `project.pbxproj` `LastUpgradeVersion`/scheme `LastUpgradeVersion = "2660"`; no `.xcode-version`/`.tool-versions`
- **Scenario**: (a) A fresh Mac or CI runner builds `mlx-swift`'s `Cmlx` target, which produces `default.metallib` (3.8 MB inside the archive's `mlx-swift_Cmlx.bundle`). Xcode 26+ ships the Metal toolchain as a separate downloadable component; here `xcodebuild -showComponent metalToolchain` reports `Status: installed`, version 27A266a. A runner without it presumably fails at the Metal step; I did not reproduce that. (b) This review used Xcode 27.1 / SDK `iphoneos27.1` (the archive records `DTXcode=2710`), while the docs and project were last upgraded by Xcode 26.6 and the documented simulator is iOS 26.5 (installed alongside 27.0). The shipped binary will carry whichever SDK built it. (c) I could not tell whether this Xcode is a release or a beta build.
- **Fix**: Record the Xcode version and the Metal toolchain step in the runbook and CI (`xcodebuild -downloadComponent MetalToolchain`); confirm the Xcode is a non-beta before uploading.
- **Blast radius**: Reproducibility; no code change.
- **Verification**: CI log shows a successful `Cmlx` build on a clean runner.

### WS-14-09 — Three first-party compiler warnings survive into the Release archive
- **Severity**: P3 · **Confidence**: CONFIRMED (seen in both the Debug-device and Release-archive logs) · **Effort**: S
- **Location**: `Views/ChatDetailView.swift:173`, `Database/DatabaseManager+Chat.swift:273`, `Database/DatabaseManager+Documents.swift:306`
- **Scenario**: The first is a real behaviour issue: `Task { _ = try await chatManager.startNewConversation() }` ignores a thrown error, so a failed "Start new chat" tap shows nothing (overlaps WS-06/WS-07). The other two are `capture of 'db' with non-Sendable type 'Connection' in a '@Sendable' closure`, the type being SQLite.swift's; fine today, but they are in Swift 6 mode and would fail a stricter compiler.
- **Evidence**:
  ```swift
  Task {
      _ = try await chatManager.startNewConversation()
  }
  ```
- **Fix**: Wrap in `do/catch` and surface via the manager's error state; leave the Sendable warnings (note them as accepted, or isolate DB access behind an actor).
- **Blast radius**: Small. Add `SWIFT_TREAT_WARNINGS_AS_ERRORS` only after these are cleared.
- **Verification**: archive log has no first-party `warning:`.

### WS-14-10 — `aps-environment = development` is declared but the app never uses remote push
- **Severity**: P3 · **Confidence**: CONFIRMED (entitlement present; grep finds no `registerForRemoteNotifications`/`PushKit`/`CloudKit`; the app only requests local-notification authorisation at `Services/DocumentProcessor.swift:1650`) · **Effort**: S
- **Location**: `HealthApp/HealthApp/HealthApp.entitlements:5`
- **Scenario**: The entitlement forces the App ID to carry the Push Notifications capability for no benefit, and a hand-signed archive would ship `development`. With automatic signing the export uses the Store profile (which has `production`), so the mismatch is not expected to break TestFlight; I could not confirm because I did not export.
- **Entitlement table (declared -> correct production value)**:

  | Entitlement | Declared | Store profile | Note |
  |---|---|---|---|
  | `aps-environment` | `development` | `production` | unused; remove it |
  | `com.apple.developer.healthkit` | `true` | `true` | needed |
  | `com.apple.developer.healthkit.access` | `[]` | present | empty is correct (no clinical records) |
  | `com.apple.developer.kernel.increased-memory-limit` | `true` | `true` | needed for MLX; capability must stay on the App ID |
  | (profile only) `healthkit.background-delivery` | not requested | `true` | harmless superset |
- **Fix**: Delete the `aps-environment` key. (WS-13 item 4 reaches the same entitlement.)
- **Blast radius**: Entitlements file and App ID capabilities; no code uses it.
- **Verification**: signed archive's `codesign -d --entitlements :-` has no `aps-environment`.

## Verified clean (checked, nothing to fix)

- **Test hooks do not ship.** Every `AppTestRuntime` flag (`--ui-testing`, `--reset-test-data`, `--skip-disclaimer`, `--seed-lab-report`, `--scripted-ai-provider`, `--disable-healthkit-sync`, `--disable-mlx-preload`) is wrapped in `#if DEBUG ... #else false/nil`, and the scripted provider and seeding code are inside `#if DEBUG`. `strings` on the Release binary finds none of the flag names (0 hits).
- **Release differs from Debug in the right ways.** Release: `-O`/WMO, `ENABLE_TESTABILITY=NO`, `STRIP_INSTALLED_PRODUCT=YES`, `STRIP_STYLE=all`, `ENABLE_NS_ASSERTIONS=NO`, `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym`, `ENABLE_DEBUG_DYLIB=NO`. No `assert`/`precondition` calls exist in app code, so disabling assertions changes nothing.
- **dSYMs.** Release produces `dSYMs/HealthApp.app.dSYM`; its UUID matches the binary; SPM dependencies link statically, so one dSYM covers them. Store it alongside each uploaded build (ASC also keeps symbols if `uploadSymbols` is true).
- **Logging.** The only log gate is `AppLog.minimumLogLevel` (`.debug` in DEBUG, `.info` otherwise, `Managers/AppLog.swift:116`); no `print`/`NSLog`. Content of log lines belongs to WS-07.
- **Swift 6 / concurrency.** `SWIFT_VERSION = 6.0` in all four targets and both configurations; no `SWIFT_STRICT_CONCURRENCY` override anywhere (Swift 6 mode implies complete checking); no `SWIFT_DEFAULT_ACTOR_ISOLATION`. Debug and Release behave the same.
- **Device family / OS.** `TARGETED_DEVICE_FAMILY = "1,2"` and `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in all targets; the built plist has `UIDeviceFamily [1,2]`, `MinimumOSVersion 26.0`, `UIRequiredDeviceCapabilities [arm64]`. iPad supports all four orientations (required for multitasking). Matches the documented "iOS 26.0+ universal".
- **Clean-checkout build.** Debug device build and Release archive both built from the committed tree with the committed `Package.resolved` (36 pins, tracked in git, no local edits needed). The scheme is shared. No run-script phases in `project.pbxproj`.
- **Usage strings.** Camera, Photos, HealthShare, LocalNetwork are present. No code path uses Face ID, location, microphone, contacts, or tracking, so no further usage keys are needed. HealthKit is read-only (`toShare: []`), so `NSHealthUpdateUsageDescription` is correctly absent.
- **Dependency pins.** `aws-sdk-swift` (`upToNextMajor` from 1.5.42, pinned 1.6.93), `SQLite.swift` (`upToNextMajor` from 0.17.0, pinned 0.17.0), `mlx-swift-lm` (`upToNextMinor` from 2.31.3, pinned 2.31.3 / revision `25b00d4e`) are version-ranged and reproducible via the tracked resolved file. `textual` is the exception (WS-14-04).

## Structural risks (max 5 bullets)

- `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` makes the app installable from the Mac App Store / TestFlight on Apple-silicon Macs, where HealthKit is unavailable and the MLX path has its own memory rules. Nothing in the review plan tests that; decide whether to opt out for the beta.
- The release procedure depends on one person's machine and keychain; there is no second path.
- MLX code is both unrunnable in the simulator and uncompiled by the default build destination, so a regression is discoverable only on a device or by the generic-iOS build.
- Behaviour differs between Debug (tested) and Release (shipped) through ~40 `#if DEBUG` sites; no test covers the Release side.
- Test targets and the app share one `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` literal set; moving to a single `.xcconfig` would remove the 8-way duplication.

## Release runbook

Run from the repo root. Everything marked **(human)** needs the account holder.

```bash
# 0. Preflight ---------------------------------------------------------------
git fetch origin && git status --short            # must be clean
git rev-parse --is-shallow-repository             # must print false (build number needs full history)
xcodebuild -version                               # record it; confirm it is a release Xcode, not a beta
xcodebuild -downloadComponent MetalToolchain      # no-op if already installed (mlx needs it)
cd HealthApp
xcodebuild -resolvePackageDependencies -project HealthApp.xcodeproj -scheme HealthApp
git diff --exit-code HealthApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved   # pins must not move
swiftlint lint --config .swiftlint.yml           # run from HealthApp/; expect the 5-violation baseline, no new ones

# 1. Builds (iPhone, iPad, and the device-only typecheck) --------------------
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5' build
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build   # typechecks MLXOnDeviceLLM/

# 2. Tests (full plan; see proposed .xctestplan below) -----------------------
xcodebuild test -project HealthApp.xcodeproj -scheme HealthApp -testPlan PreRelease \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath ../build/PreRelease.xcresult
# read the real count from the .xcresult, not stdout:
xcrun xcresulttool get test-results summary --path ../build/PreRelease.xcresult

# 3. Version / build number --------------------------------------------------
export BUILD=$(git rev-list --count HEAD)         # monotonic; 583 at f95cf804
# MARKETING_VERSION: edit only for a new train (project.pbxproj :1111 and :1153), commit, tag vX.Y
echo "Archiving build $BUILD"

# 4. Archive (signed; needs (human) distribution signing, see WS-14-06) --------
xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath ../build/BisonHealth-$BUILD.xcarchive \
  CURRENT_PROJECT_VERSION=$BUILD -allowProvisioningUpdates clean archive
plutil -p ../build/BisonHealth-$BUILD.xcarchive/Products/Applications/HealthApp.app/Info.plist | grep -E "CFBundle(Short)?Version|ITSApp"
codesign -d --entitlements :- ../build/BisonHealth-$BUILD.xcarchive/Products/Applications/HealthApp.app   # expect no aps-environment after WS-14-10, get-task-allow absent
dwarfdump --uuid ../build/BisonHealth-$BUILD.xcarchive/dSYMs/HealthApp.app.dSYM

# 5. Export + upload ---------------------------------------------------------
xcodebuild -exportArchive -archivePath ../build/BisonHealth-$BUILD.xcarchive \
  -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
# optional pre-check: xcrun altool --validate-app -f <ipa> -t ios --apiKey ... --apiIssuer ...
# keep ../build/BisonHealth-$BUILD.xcarchive (it holds the dSYM) for as long as the build is installable
```

`ExportOptions.plist` (proposed, not in the repo):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>4W55VW7UXX</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
```
`manageAppVersionAndBuildNumber=false` keeps Xcode from rewriting the build number you passed in (its default is to manage it; I have not exercised this key).

**App Store Connect steps (human)**
1. App record exists for `com.bisonhealthai.app` (create it first if not); iPhone and iPad screenshots are required because the app is universal.
2. Wait for processing, then the build appears under TestFlight. If it says "Missing Compliance", WS-14-02 is not fixed yet; answer the encryption questionnaire.
3. Test Information: What to Test (what changed, in plain words), beta app description, feedback email, and **Beta App Review notes**: it is a health data app; give the reviewer the steps to reach AI chat without a Bedrock key (use on-device or a demo server), say that HealthKit is read-only, and that MLX model download occurs on first use. Add a privacy policy URL.
4. Internal testers first (no review). For external testers create a group, add the build, submit for Beta App Review (first build of each version).
5. Version/What's-new text is per version, not per build.

**Post-upload verification (needs a real device)**
1. Install from TestFlight on an iPhone and an iPad (not from Xcode).
2. Smoke flow: first launch and disclaimer; database opens (no `DatabaseUnavailableView`); import a PDF and a photo; review sheet; chat with each provider you intend to test; HealthKit authorisation prompt; on-device model download and one reply (the only place MLX runs).
3. Kill and relaunch once. Check for a crash-free launch in TestFlight / Xcode Organizer > Crashes after a few hours.
4. Confirm a crash symbolicates: Organizer needs the uploaded dSYM; for a spot check, `atos -arch arm64 -o <dSYM>/Contents/Resources/DWARF/HealthApp -l <loadaddr> <addr>`.

**Rollback**
- You cannot recall a build from a tester's phone, but you can stop new installs: ASC > TestFlight > the build > **Expire Build** (or remove it from the group), then re-enable the last good build for the group.
- Fix forward: new commit, new `BUILD` (the number must be higher than the bad one; do not reuse), upload, and promote.
- Database safety: a build with a *higher* DB version cannot be reverted by shipping a lower one. `DatabaseManager` refuses a newer-than-known database (`DatabaseUnavailableView`), so never ship a schema bump you are not ready to keep.
- If the bad build corrupted data, there is no iCloud backup (by design); ask testers to export from Settings first, if that exists.

## Proposed CI workflow (file body; do not create it yet)

`.github/workflows/ci.yml`. Unverified: the runner image name and which Xcode it ships; pin the Xcode with `xcode-select` after checking the runner's list.

```yaml
name: ci
on:
  pull_request:
  push: { branches: [main] }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  build-test:
    runs-on: macos-26            # confirm the image and its installed Xcode before relying on this
    timeout-minutes: 60
    defaults: { run: { working-directory: HealthApp } }
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Select Xcode and tools
        run: |
          ls /Applications | grep -i xcode
          sudo xcode-select -s /Applications/Xcode.app    # replace with the pinned version
          xcodebuild -version
          xcodebuild -downloadComponent MetalToolchain || true
          brew install swiftlint || true
      - name: Resolve packages (pinned)
        run: xcodebuild -resolvePackageDependencies -project HealthApp.xcodeproj -scheme HealthApp -onlyUsePackageVersionsFromResolvedFile
      - name: Lint
        run: swiftlint lint --config .swiftlint.yml --strict
      - name: Build iPhone
        run: xcodebuild build -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -onlyUsePackageVersionsFromResolvedFile
      - name: Build iPad
        run: xcodebuild build -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5' -onlyUsePackageVersionsFromResolvedFile
      - name: Typecheck device-only code (MLX)
        run: xcodebuild build -project HealthApp.xcodeproj -scheme HealthApp -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -onlyUsePackageVersionsFromResolvedFile
      - name: Release archive compiles (unsigned)
        run: xcodebuild archive -project HealthApp.xcodeproj -scheme HealthApp -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO -archivePath $RUNNER_TEMP/ci.xcarchive CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)
      - name: Fast tests
        run: xcodebuild test -project HealthApp.xcodeproj -scheme HealthApp -testPlan Fast -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -resultBundlePath $RUNNER_TEMP/fast.xcresult
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: fast-xcresult, path: ${{ runner.temp }}/fast.xcresult }
```
Caveat: `--strict` makes the 5 baseline violations fatal if the baseline is not applied from `HealthApp/`; drop `--strict` if lint then fails.

## Proposed test plan(s)

The repo has one shared scheme and no `.xctestplan`. Two plans, referencing the existing targets by their `project.pbxproj` blueprint IDs (`A1000037294A0000000000001` = HealthAppTests, `UITESTTARGET001` = HealthAppUITests). I did not run these and I did not measure per-file runtime, so which files are "slow" is a guess; start with everything in Fast and move files out once timings are known.

`HealthApp/Fast.xctestplan` (PR gate: all 16 unit files, no UI test, parallel):

```json
{
  "configurations": [ { "id": "A3D8E0F2-0000-4000-8000-000000000001", "name": "Default", "options": {} } ],
  "defaultOptions": { "codeCoverage": false },
  "testTargets": [
    { "parallelizable": true,
      "target": { "containerPath": "container:HealthApp.xcodeproj", "identifier": "A1000037294A0000000000001", "name": "HealthAppTests" } }
  ],
  "version": 1
}
```

`HealthApp/PreRelease.xctestplan` (before every upload: the unit bundle plus the UI smoke test; run on iPhone and then iPad):

```json
{
  "configurations": [ { "id": "A3D8E0F2-0000-4000-8000-000000000002", "name": "Default", "options": {} } ],
  "defaultOptions": { "codeCoverage": true },
  "testTargets": [
    { "parallelizable": true,
      "target": { "containerPath": "container:HealthApp.xcodeproj", "identifier": "A1000037294A0000000000001", "name": "HealthAppTests" } },
    { "target": { "containerPath": "container:HealthApp.xcodeproj", "identifier": "UITESTTARGET001", "name": "HealthAppUITests" } }
  ],
  "version": 1
}
```
Needs a simulator and a specific destination: `RegressionSmokeUITests` (UI), `AccessibilityTests`, and anything touching the keychain or file protection; the 6 UI files that are not target members would be added to `PreRelease` once tracker item 25 is done. Both plans run Debug, so the Release side stays covered only by the archive step.

## Machine-readable summary
```json
[
  {"id":"WS-14-01","title":"Build number hard-coded to 1 in 8 settings; repeated upload collides","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1131","HealthApp/HealthApp.xcodeproj/project.pbxproj:1089"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-02","title":"ITSAppUsesNonExemptEncryption absent; every TestFlight build holds at Missing Compliance","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1094","HealthApp/HealthApp/Info.plist"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-03","title":"No app privacy manifest while UserDefaults and file-timestamp APIs are used","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/HealthAppApp.swift:289","HealthApp/HealthApp/Managers/AppLog.swift:679"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-04","title":"textual dependency tracks fork main; fork is 34 commits past the pin","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1300","HealthApp/HealthApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved:311"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-05","title":"No CI, no test plan; nothing exercises Release or the device-only MLX code","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/xcshareddata/xcschemes/HealthApp.xcscheme"],"effort":"M","area":"build-testflight"},
  {"id":"WS-14-06","title":"Signed archive/export path unproven; no distribution identity in keychain, no ExportOptions","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1088"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-07","title":"1024 App Store icon is RGBA (opaque, but alpha channel present)","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Assets.xcassets/AppIcon-BisonHealthAI-Pro.appiconset/AppIcon-BisonHealthAI-Pro-1024.png"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-08","title":"Toolchain prerequisites unrecorded (Metal toolchain download, Xcode 27.1 vs documented 26.x, beta status unknown)","severity":"P2","confidence":"PLAUSIBLE","files":["CLAUDE.md","HealthApp/HealthApp.xcodeproj/xcshareddata/xcschemes/HealthApp.xcscheme"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-09","title":"Three first-party compiler warnings in Release, one a swallowed startNewConversation error","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:173","HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:273","HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:306"],"effort":"S","area":"build-testflight"},
  {"id":"WS-14-10","title":"aps-environment=development entitlement declared but remote push is unused","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/HealthApp.entitlements:5"],"effort":"S","area":"build-testflight"}
]
```
