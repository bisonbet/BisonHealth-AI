# WS-16 — Docs & plan drift

- **Agent / model**: Claude (Sonnet 5.5), subagent run
- **Date**: 2026-10-24
- **Commit reviewed**: f95cf804
- **Scope actually covered**: `README.md`, `CLAUDE.md`, `.claude/CLAUDE.md` (git-tracked as lowercase `.claude/claude.md`), `AGENTS.md`, `AGENT_CODEBASE_INSTRUCTIONS.md`, `CONTRIBUTING.md`, `PRE-BETA-REVIEW.md` (first 60 lines + headings), `Personas-Prompts/README.md`, `Views/PrivacyPolicyView.swift`, `Views/TermsOfServiceView.swift`, `Documentation/Archive/hipaa-positioning-webpage.html`, `Documentation/Review/TRACKER.md`, `BETA-RELEASE-REVIEW-PLAN.md` §0/§1/§5, `Documentation/Review/README.md`. Claims checked against `DatabaseManager`, `FileSystemManager`, `Keychain`, `SettingsManager`, `BedrockClient`, `MLXOnDeviceClient`, `MLXModelDownloadManager`, `Info.plist`, entitlements, `project.pbxproj`, the 12 commits since 2026-10-22, and by running `xcodebuild -showdestinations/-showBuildSettings` (no simulator booted, no build run).
- **Scope not covered**: `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` (does not exist, see WS-16-13). The full body of `PRE-BETA-REVIEW.md` (252 lines) was not re-verified claim by claim. `HealthApp/HealthApp/Database/README_Disclaimer_Management.md` not read. Emoji/UI strings in views other than the ones grepped (`encrypt`, `Hugging Face`, `never leaves`, `HIPAA`, `No internet`) were not audited. I did **not** run the `generic/platform=iOS` MLX typecheck command from the TRACKER (heavy build; other agents share DerivedData), so that command is unverified. I did not run a full `xcodebuild build/test`; destinations and project discovery were verified with `-showdestinations` / `-showBuildSettings` only. The claim that `Personas-Prompts/*.txt` match `Doctor.swift` text was not checked (README says prompts "are loaded via `Doctor.swift`"; the prompts are inline Swift strings, the .txt files are reference copies).
- **Verdict**: Not beta-ready as documentation. The README and Privacy Policy were corrected on 2026-10-23, but `CLAUDE.md` still states the pre-v13 privacy model, three confirmed user-facing strings still make false data-handling claims (a backup that is never made, "permanently deleted", "encrypted"), and the legal copy carries a July date over October text.
- **Counts**: P0=0 P1=3 P2=7 P3=5 (dropped: 0; two minor items folded into WS-16-13 and WS-16-14)

Severity follows the WS-16 prompt: privacy/data-safety misstatement = P1; wrong command or stale version that misleads an agent = P2; rest P3.

## Findings

### WS-16-01 — Reset Database dialog promises a backup that is never made, and the success message says "All health data" is deleted while document files and thumbnails remain
- **Severity**: P1 · **Confidence**: CONFIRMED (message text and code path); thumbnails-remain is CONFIRMED by reading, not by running · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/SettingsView.swift:50` and `:1025`; `HealthApp/HealthApp/Database/DatabaseManager.swift:776-814`
- **Scenario**: A tester taps Reset Database. The confirmation says "A backup will be created first." No backup is created: `resetDatabase()` calls `deleteMigrationBackups()` and removes the database, nothing writes a backup. The user proceeds believing a safety net exists. After success the app says "All health data has been permanently deleted", but `resetDatabase()` touches only the SQLite file and its `-wal`/`-shm`. The files under `Documents/HealthApp/Documents/Imported/` (AES-GCM blobs, key still in Keychain), and `Documents/Thumbnails/*_thumb.jpg` (plaintext page-1 JPEGs, per `FileSystemManager.swift:244-312`) are left on disk and in device backups until the separate manual "orphan cleanup" runs. TRACKER item 10 is marked "fixed (65ec1f23)", but its own description lists both "promises a backup it never makes" and "leaves documents on disk"; only the in-memory half was fixed.
- **Evidence**:
  ```swift
  // SettingsView.swift:50
  case .database: return "⚠️ WARNING: This will permanently delete ALL your health data, documents, and chat history. This action cannot be undone. A backup will be created first."
  // SettingsView.swift:1025
  successMessage = "Database has been reset successfully. All health data has been permanently deleted."
  // DatabaseManager.swift:786-795 -- deletes only databaseURL + "-wal" + "-shm"
  ```
- **Fix**: Replace the dialog text with: "This will permanently delete ALL your health data, documents, and chat history from this device. This action cannot be undone. No backup is made." Either make `resetDatabase()`'s caller also delete `Documents/Imported` and `Documents/Thumbnails` (then the success text becomes true), or change the success text to "Database reset. Imported document files remain until you clear storage." Re-open TRACKER item 10 as "partly fixed".
- **Blast radius**: `SettingsView.swift`, `DatabaseUnavailableView.swift:234` (erase-and-rebuild has the same file-leftover behaviour), the Privacy Policy "Your Rights" section (promises deletion through the app).
- **Verification**: Import a document, Reset Database, then list the app container's `Documents/HealthApp/Documents/*`: both directories must be empty (or the text must say they are not).

### WS-16-02 — "Encrypted" is claimed without qualification in six places; thumbnails, tags and on-disk filenames are plaintext
- **Severity**: P1 · **Confidence**: CONFIRMED · **Effort**: S (wording) / M (closing the gap, already TRACKER item 21)
- **Location**: `PrivacyPolicyView.swift:23`; `FirstLaunchDisclaimerView.swift:153`; `README.md:192` and `:320`; `CLAUDE.md:419` ("CryptoKit for **all** health data"); `CONTRIBUTING.md:400`
- **Scenario**: A reviewer or user reads "The app encrypts health data, documents, chats, and appointment prep records." A page-1 JPEG of every imported document is written unencrypted to `Documents/Thumbnails` (and, unlike the migration backup, is not excluded from device backups: `isExcludedFromBackup` is set only on logs and the migration backup). The imported file's original name is embedded in the on-disk name (`UUID_<sanitizedFileName>`, `FileSystemManager.swift:131-134`), and thumbnail names too (`:300`). Document and conversation `tags` are stored in plaintext columns (`DatabaseManager.swift:80,111`). A lab PDF's first page, name and tags are readable without the key. The Privacy Policy also says backups contain the database "in encrypted form", omitting these files.
- **Evidence**:
  ```swift
  // FileSystemManager.swift:244, 272, 294, 312
  try thumbnailData.write(to: thumbnailURL)      // no encryptData(), no exclude-from-backup
  // FileSystemManager.swift:131-134
  finalFileName = "\(UUID().uuidString)_\(sanitizedFileName)"   // original filename in plaintext path
  ```
- **Fix**: Replace `PrivacyPolicyView.swift:23` sentence with: "The app encrypts the text of your health data, document files, extracted document text, chats, and appointment prep records before storing them. Document thumbnails, document names and tags are not encrypted by the app; they are protected only by iOS device encryption." Same wording in `FirstLaunchDisclaimerView.swift:153`; README line 192 -> "Health records, documents and chats are encrypted at rest (thumbnails and tags are not yet)"; README 320 -> "Encryption - Health records, imported documents and chats are encrypted with CryptoKit; thumbnails and tags are not (tracked)"; `CLAUDE.md:419` -> "CryptoKit for health records, document files, extracted text, chat messages/titles, appointment preps. NOT encrypted: thumbnails, tags, original filenames in on-disk names (TRACKER item 21)." Remove the claim again once item 21 lands.
- **Blast radius**: App Store privacy-policy URL/metadata copy derived from these strings; WS-13 submission answers.
- **Verification**: After wording change, grep the repo for `encrypt` in docs and `Text(` strings and confirm each qualified; after item 21, list `Documents/Thumbnails` and confirm absent or ciphertext.

### WS-16-03 — CLAUDE.md still says there is no iCloud backup and "all data on-device"; the v13 key-sync change made both untrue
- **Severity**: P1 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `CLAUDE.md:13`, `:421-423` (Backup, Secrets, Network lines); contradicted by `Utils/Keychain.swift:63-75` and commit 3c857bbb
- **Scenario**: `CLAUDE.md` is loaded into every agent's context. An agent told "Backup: On-device only (iCloud/CloudKit backup removed...)" and "Privacy: Local-first, all data on-device" may "harden" the key back to `ThisDeviceOnly` (re-creating the restore-destroys-all-data bug, TRACKER item 8), may omit key sync from a privacy review, or may write App Store copy saying nothing leaves the device. In fact the encrypted database is in iOS device backups, the database key syncs through iCloud Keychain (`kSecAttrAccessibleAfterFirstUnlock`, synchronizable), and chat context is sent to Bedrock / an OpenAI-compatible server when the user selects one. Also "removed - no BAA available" repeats the HIPAA-flavoured rationale TRACKER item 22 flagged as contradicting the non-HIPAA stance.
- **Evidence**:
  ```
  CLAUDE.md:13   - **Privacy**: Local-first, all data on-device (no iCloud/CloudKit backup)
  CLAUDE.md:422  - **Backup**: On-device only (iCloud/CloudKit backup removed — no BAA available)
  Keychain.swift:73  // through the user's iCloud Keychain. That is a deliberate trade and the privacy
  ```
- **Fix**: Replace line 13 with: "**Privacy**: Local-first. On-device by default; chat context leaves the device only if the user selects Bedrock or an OpenAI-compatible server (the chat screen shows which, and asks once before the first cloud send). No CloudKit record sync." Replace line 422 with: "**Backup/key**: The encrypted database is included in normal device backups. The database key is stored synchronizable (iCloud Keychain) so a restore can read it; do NOT change it to `ThisDeviceOnly` (see `Keychain.swift` header comment). API keys stay device-only." Add: "**Egress**: AI provider you configure; iCloud Keychain (key only); device backups; Hugging Face (model download only); genetics reference link (asks first); user exports."
- **Blast radius**: any agent session; WS-07/13 privacy statements.
- **Verification**: Re-read CLAUDE.md Privacy section against `Keychain.swift` and `PrivacyPolicyView.swift:25-37`; they should list the same egress set.

### WS-16-04 — Privacy Policy and Terms say "Last updated: July 3, 2026" but the policy text changed on 2026-10-23
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `PrivacyPolicyView.swift:11`, `TermsOfServiceView.swift:16`
- **Scenario**: Commit 3c857bbb (2026-10-23) rewrote the "Local Storage" section to disclose iCloud Keychain key sync, device backups, Hugging Face and the genetics link. The date was not touched. An App Review or user comparing dates sees a policy that claims to predate a material data-handling change. `git log` for the file: 3c857bbb (2026-10-23), then 1cb3008a (2026-07-03).
- **Evidence**: `Text("Last updated: July 3, 2026")` in both files.
- **Fix**: Set both to the date of the release that ships the new text (and again when TRACKER item 22's remaining Terms/Policy edits land). Consider a single `BisonHealthLegalCopy.lastUpdated` constant (already the home of shared legal strings in `FirstLaunchDisclaimerView.swift`).
- **Blast radius**: none beyond the two views; the App Store Connect privacy URL must match.
- **Verification**: grep `Last updated` in Views.

### WS-16-05 — In-app copy says loading an on-device model contacts Hugging Face; since 330bebf9 it does not
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `PrivacyPolicyView.swift:33`; `Views/OnDeviceLLMSettingsView.swift:135`; `MLXOnDeviceClient.swift:585-588`
- **Scenario**: Load now uses `ModelConfiguration(directory: modelDirectory, ...)` with no network. The policy still says "Downloading an on-device model, and loading one, contacts Hugging Face to fetch or verify the model files", and the settings screen says "Downloading or loading a model contacts Hugging Face." Over-disclosure, not under-disclosure, so low harm, but it contradicts the TRACKER (item 28 "fixed", whose Files column lists "privacy policy") and `Views/SettingsView.swift:241` ("No internet required after downloading", now true), and it will make the privacy-label answers (WS-13) inconsistent. Caveat: the load path is inside `#if !targetEnvironment(simulator)` and was never run on a device (TRACKER header says so), so "does not contact" is CONFIRMED by reading only.
- **Evidence**:
  ```swift
  // MLXOnDeviceClient.swift:585
  let configuration = ModelConfiguration(
      directory: modelDirectory,
      extraEOSTokens: selectedModel.extraEOSTokens
  )
  ```
- **Fix**: Policy: "Downloading an on-device model contacts Hugging Face to fetch the model files. Loading and running a downloaded model does not use the network. No health data is sent." Settings view: "...Downloading a model contacts Hugging Face; chats then run entirely on this device." Do this only after a device run confirms offline load.
- **Blast radius**: 2 strings; TRACKER item 28 and 22 status text.
- **Verification**: On a device, airplane mode, load model, ask a question; Settings copy matches.

### WS-16-06 — CLAUDE.md database version: 10 / 12 / 11 / 12, real value is 13
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `CLAUDE.md:10`, `:111`, `:127`, `:313-314`, `:529`; authority `DatabaseManager.swift:47`
- **Scenario**: Four different numbers in one file, none correct. An agent adding a migration reads "current is 12", writes `case 13:` (already taken by `pending_import_reviews`), and either collides or, with `currentDatabaseVersion = 13`, silently never runs its migration for existing installs. The example also says `private static let` where the real declaration is `internal static` (tests read it), and `performMigration` is a `switch` with `case N:` branches (which the doc gets right).
- **Evidence**:
  ```swift
  // DatabaseManager.swift:47
  internal static let currentDatabaseVersion = 13 // Increment when making schema changes
  ```
- **Fix**: Line 10 -> "(current version: 13)"; line 111 -> "**Current Database Version**: 13"; lines 127 and 313 -> `internal static let currentDatabaseVersion = 14  // Was 13` with `case 14:`; line 529 -> "Database version: 13". Better: delete the hard-coded number in 10/529 and say "see `DatabaseManager.currentDatabaseVersion`" (the tests already assert against the constant, `DatabaseTests.swift:175`). Also add `appointment_preps` (v8) and `pending_import_reviews` (v13) to the Key Tables list and `+AppointmentPrep`, `+Recovery` to the Extensions list (`CLAUDE.md:278-290`). Same fix in the plan, §0 table row "Database" (says 12), and README-style "Current project facts".
- **Blast radius**: every agent that touches schema.
- **Verification**: `grep -n "currentDatabaseVersion" HealthApp/HealthApp/Database/DatabaseManager.swift` equals every number in the docs.

### WS-16-07 — Build/test commands: wrong simulator, wrong working directory, duplicated "UI" command
- **Severity**: P2 · **Confidence**: CONFIRMED (ran `xcodebuild -showBuildSettings` / `-showdestinations`) · **Effort**: S
- **Location**: `CLAUDE.md:399-405`, `:460`; `AGENTS.md:19-20`; `README.md:290-294`
- **Scenario**: (a) `iPad Pro 11-inch (M4)` does not exist on this machine: `xcodebuild ... -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' -showBuildSettings` fails with "Unable to find a device matching the provided destination specifier" (installed: iPad Pro 11-inch (M5), iPad Air 11-inch (M4)). The same file's build section uses `(M5)`; Troubleshooting (`:460`) and `CLAUDE.md` project text say M4. (b) All test commands omit `cd HealthApp` and `-project`; from the repo root, where the docs say to work (`open HealthApp/HealthApp.xcodeproj`), `xcodebuild -scheme HealthApp ...` fails with "The directory /Users/champ/Sources/BisonHealth-AI does not contain an Xcode project". (c) `README.md:290-294` lists two byte-identical commands as "unit" and "UI" tests. (d) `iPad Pro 11-inch (M5)` exists for both iOS 26.5 and 27.0 runtimes, so the destination without `OS=` is ambiguous; the build commands pin `OS=26.5`, the test commands do not.
- **Evidence**:
  ```
  xcodebuild: error: The directory /Users/champ/Sources/BisonHealth-AI does not contain an Xcode project, workspace or package.
  xcodebuild: error: Could not configure request to show build settings: Unable to find a device matching the provided destination specifier (iPad Pro 11-inch (M4))
  ```
- **Fix**: One canonical block, in `CLAUDE.md` only (the plan §0 already has the right form): `cd HealthApp && xcodebuild test -project HealthApp.xcodeproj -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'` and the same with `iPad Pro 11-inch (M5),OS=26.5`. Replace both `(M4)` occurrences. In README and AGENTS replace their command lines with "see CLAUDE.md §Build Commands". README "Run UI tests": either delete, or note only `RegressionSmokeUITests` (2 tests) is in the UI target (see WS-16-13).
- **Blast radius**: README, AGENTS, CLAUDE; the plan and FIX protocol already use the correct form.
- **Verification**: Paste each documented command into a shell at the documented directory with `-showBuildSettings` appended; all must resolve.

### WS-16-08 — CONTRIBUTING.md's setup and test commands cannot work in this repo
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `CONTRIBUTING.md:56`, `:64`, `:67`, `:153`, `:206`, `:390`, `:410`
- **Scenario**: `open BisonHealthAI.xcodeproj` (no such project; it is `HealthApp/HealthApp.xcodeproj`); `-scheme BisonHealthAI` and `-scheme BisonHealthAIUITests` (only scheme is `HealthApp`); simulator `iPhone 15` (not installed; runtimes are 26.5/27.0 with iPhone 17 family); "Check the `/Docs/` directory" (the directory is `Documentation/`). The SwiftUI example uses `NavigationView` (`:153`), which CLAUDE.md forbids; the file-protection example uses `FileProtectionType.complete` (`:206`) whereas the app uses `completeUntilFirstUserAuthentication` (`FileSystemManager.swift:105,147`); the security contact `security@bisonhealth.ai` differs from the app's `support@bisonnetworking.com` (PrivacyPolicyView.swift:82), and no mailbox for the former is evidenced anywhere in the repo (UNVERIFIED whether it exists). Its "Security Guidelines" say "Use encryption for all health data storage", repeating WS-16-02. It has no Definition of Done, which CLAUDE.md, AGENTS.md and AGENT_CODEBASE_INSTRUCTIONS.md all carry verbatim.
- **Evidence**: `open BisonHealthAI.xcodeproj` / `xcodebuild test -scheme BisonHealthAI -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Fix**: Replace `:56` with `open HealthApp/HealthApp.xcodeproj`; replace `:61-68` with "Run the commands in CLAUDE.md §Build Commands / §Running Tests"; change `NavigationView` to `NavigationStack`; `:206` to `.completeUntilFirstUserAuthentication`; `:410` "`Documentation/`"; confirm or replace the security address; add a pointer "Definition of Done: see CLAUDE.md".
- **Blast radius**: external contributors only (agents are not told to read it, but CLAUDE.md lists it at `:509`).
- **Verification**: Follow CONTRIBUTING from a clean clone.

### WS-16-09 — CLAUDE.md component tables and recipes name APIs that do not exist or have different shapes
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `CLAUDE.md:56-66`, `:258`, `:332-353`, `:367`, `:374`, `:272`
- **Scenario**: Agents copy these recipes. (a) `protocol AIProviderInterface` is shown as non-isolated with `sendMessage(_:context:) -> String` and non-throwing `testConnection() -> Bool`; real: `@MainActor protocol AIProviderInterface: ObservableObject, Sendable` with `testConnection() async throws -> Bool`, `sendMessage(_:context:conversationHistory:) -> AIResponse`, `getCapabilities()`, `updateConfiguration(_:)` (`Services/AIProviderInterface.swift:9-18`). A new client written to the doc will not compile. (b) "Update `AIChatManager.getAIClient()`" -- `AIProvider` and `getAIClient()` live in `SettingsManager.swift:72,441`, not `AIChatManager`. (c) `HealthDataManager.loadBloodTests()` does not exist (`addBloodTest/updateBloodTest/deleteBloodTest/loadHealthData`). `AIChatManager.sendMessage()` is `sendMessage(_:useStreaming:)`; `generate()` is `generate(for:)`. (d) Bedrock models "Claude Sonnet 4, Llama 4 Maverick"; real: Claude Sonnet 4.5 (`global.anthropic.claude-sonnet-4-5-20250929-v1:0`), Llama 4 Maverick, Amazon Nova Premier (`BedrockClient.swift:11-13`; README is correct). (e) "Formats: PDF, DOCX, images (JPEG, PNG, HEIC)": the import picker allows only `[.pdf, .image]` (`ContentView.swift:616`) and `NativeDocumentExtractor.swift:244-246` routes `.doc/.docx` to PDFKit, which cannot open them, so DOCX is not a supported import. (f) `MedicalDocumentExtractor` listed as "N/A (local)": it drives the configured AI provider (README calls it "AI-Enhanced"), so it is local only when the on-device provider is selected. (g) "Adding a New Health Data Type" recipe says to add a table in a migration; existing types share `health_data` with a type column.
- **Evidence**:
  ```swift
  // CLAUDE.md:63-64
  func sendMessage(_ message: String, context: String) async throws -> String
  func testConnection() async -> Bool
  // AIProviderInterface.swift:15-16
  func testConnection() async throws -> Bool
  func sendMessage(_ message: String, context: String, conversationHistory: [ChatMessage]) async throws -> AIResponse
  ```
- **Fix**: Replace the protocol snippet with the real 6-member protocol; in "Adding a New AI Provider" step 2/3 say "`AIProvider` enum and `getAIClient()` in `Managers/SettingsManager.swift`"; replace `loadBloodTests()` with `addBloodTest()`; Bedrock line -> "Claude Sonnet 4.5, Llama 4 Maverick, Amazon Nova Premier"; Formats -> "PDF, images (JPEG, PNG, HEIC)"; `MedicalDocumentExtractor` endpoint -> "Configured extraction provider (on-device by default)".
- **Blast radius**: any agent adding a provider or data type.
- **Verification**: `grep` each backticked symbol in the file against `HealthApp/HealthApp`; none may be missing (run the table in this report).

### WS-16-10 — The rule that most affects verification is absent from CLAUDE.md: MLX files compile out of simulator builds
- **Severity**: P2 · **Confidence**: CONFIRMED (TRACKER header, `MLXOnDeviceClient.swift` and `MLXModelDownloadManager.swift` are inside `#if !targetEnvironment(simulator)` per commit 330bebf9); the typecheck command itself is UNVERIFIED (not run) · **Effort**: S
- **Location**: absent from `CLAUDE.md`; present only in `Documentation/Review/TRACKER.md:30-45` and the fix protocol
- **Scenario**: CLAUDE.md's Build Commands are simulator-only. An agent editing `MLX*.swift` follows them, gets "BUILD SUCCEEDED", and reports verified, which is exactly the failure the TRACKER records for items 27-29 ("every MLX review and fix before this one was validated by a build that skipped the code under change"). The same applies to the SwiftLint working directory (`.swiftlint.yml` is in `HealthApp/`, not repo root; AGENTS.md has it right, CLAUDE.md never mentions SwiftLint) and the baseline of 5 violations.
- **Evidence**: `TRACKER.md:32-34` "a simulator build compiles none of their substance".
- **Fix**: Add to CLAUDE.md §Build Commands: "MLX files (`MLXOnDeviceLLM/*`) are inside `#if !targetEnvironment(simulator)`; a simulator build does not compile them. After touching them also run: `cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build`. They can only be exercised on a device." And: "Lint: `cd HealthApp && swiftlint lint --config .swiftlint.yml` (baseline: 5 violations)."
- **Blast radius**: MLX work items 27-29 and any future MLX change.
- **Verification**: Run the added command once to prove it as written; this review did not.

### WS-16-11 — "TLS 1.2+ only" / "Network calls must use TLS" is false for LAN servers
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `CLAUDE.md:423`; `AGENTS.md:56`; contradicted by `Info.plist:24` (`NSAllowsLocalNetworking`) and `OpenAICompatibleClient.swift:42,58`
- **Scenario**: The app deliberately allows cleartext `http://` to private-range / `.local` hosts so self-hosted Ollama/LM Studio work; chat context (health data) then crosses the LAN unencrypted. The docs say TLS only, so an agent or reviewer will not list the cleartext path in the privacy review or the App Store answers. No code sets `tlsMinimumSupportedProtocolVersion` (grep: none); the "1.2+" is the ATS platform default for public hosts, not an app setting.
- **Evidence**:
  ```swift
  // OpenAICompatibleClient.swift:58
  if scheme == "http", !Self.isPrivateNetworkHost(host) {   // http allowed only for private hosts
  ```
- **Fix**: CLAUDE.md:423 -> "**Network**: Public hosts must be HTTPS (ATS). The OpenAI-compatible client also allows cleartext HTTP to private-network/`.local` hosts (`NSAllowsLocalNetworking`, `OpenAICompatibleEndpointValidator`), so health context sent to a LAN server is unencrypted in transit." AGENTS.md:56 -> "Network calls to public hosts must use TLS; the only cleartext exception is private-network OpenAI-compatible servers." Disclose the LAN case in the Privacy Policy "AI provider" bullet.
- **Blast radius**: privacy policy, WS-13 ATS justification text.
- **Verification**: Review text against `Info.plist` and the validator.

### WS-16-12 — Archived HIPAA positioning page still says all data stays on the device
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Documentation/Archive/hipaa-positioning-webpage.html` ("Local-First - All sensitive data stays on your device", "Local Storage - All data stays on your device", "No Tracking - No analytics, tracking, or data collection", CTA "Download for iOS")
- **Scenario**: The page's HIPAA stance is consistent with the app (no BAA, personal use only; no contradiction there). Its privacy lines are the pre-fix claims TRACKER item 22 / decision 2 withdrew: with a cloud provider configured, or key sync on, "all data stays on your device" is false. It is a ready-to-host page with a download button, which is how stale claims reach App Store metadata. It also has no date or "archived" banner in the HTML.
- **Fix**: Either delete the two lines or reword to the README's: "On-device by default. Your data leaves the device only where you configure it: a cloud AI provider, and your encryption key via iCloud Keychain." Add `<!-- ARCHIVED: do not publish; claims superseded by README Privacy section -->` at the top.
- **Blast radius**: marketing/website reuse.
- **Verification**: grep the file for "stays on your device".

### WS-16-13 — TRACKER, review README and plan §0 have drifted from each other and from the code
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `TRACKER.md:132-134`, `:142-144`, `:162-169`; `Documentation/Review/README.md` ("TRACKER.md ... empty until WS-17 triage runs"); `BETA-RELEASE-REVIEW-PLAN.md` §0 rows "Database" (12), "App source" (~51,800 LOC), "Hygiene" (5 `@unchecked Sendable`)
- **Scenario**: The header block (`TRACKER.md:3-28`) was updated on 2026-10-23 and its arithmetic checks out: Status column has 23 fixed / 3 partly (13, 21, 22) / 6 open (11, 12, 25, 30, 31, 32) = 32. But below it: line 132-134 still reads "Paused here at the owner's request. Remaining: WS-10, WS-11, WS-13-WS-16" (WS-12 done, fix passes done); line 142-144 says the worklist is "24 work items" (header says 32); the Workstream-status table says WS-13/WS-14 "not started" while `findings/WS-13-appstore-compliance.md` and `WS-14-build-testflight.md` now exist (untracked); items 31 and 32 appear only in the v13 table, not in the worklist table; the header says WS-16 "never run" (this report). The review README says the tracker is empty. Plan §0: DB version 12 (now 13); source ~51,800 LOC (`cat` of the 124 files = 53,098 lines; plan's counting method not stated, so UNVERIFIED as drift); `@unchecked Sendable` 5 in plan, 3 in the TRACKER re-grade, 4 real declarations now (`MLXModelDownloadManager.swift:1353`, `AppLog.swift:68`, `MedicalDocument.swift:18`, `NativeDocumentExtractor.swift:469`). Item 10's Status ("fixed") overstates, see WS-16-01; item 28's Files column lists "privacy policy" but the policy still carries the old text, see WS-16-05.
- **Fix**: Replace `TRACKER.md:132-134` with "Status 2026-10-24: fix passes 1-3 and the v13 work landed; WS-13, WS-14, WS-16 reports filed; WS-10, WS-11, WS-15, WS-17 not yet run." Line 142-144: "merges ... into 32 work items". Mark WS-13/14/16 rows `complete` with links when their files are committed. Plan §0: "currentDatabaseVersion = 13"; recount LOC and `@unchecked Sendable` (4). Review README: "TRACKER.md - the live worklist (32 items; see its header)".
- **Blast radius**: orchestration only.
- **Verification**: Recount the Status column after edits.

### WS-16-14 — AGENTS.md / AGENT_CODEBASE_INSTRUCTIONS.md reference a directory and logging API that do not exist; "CI expectations" with no CI
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `AGENTS.md:7-14,22,41-42,64`; `AGENT_CODEBASE_INSTRUCTIONS.md:25,125,140,152,160-168`; `AGENTS.md` "CI expectations"; `CONTRIBUTING.md:363`
- **Scenario**: Both docs tell agents about `legacy/` (and `cd legacy/web-app && npm i`); there is no `legacy/` directory in the tree. `AGENT_CODEBASE_INSTRUCTIONS.md` tells agents to "use `print()` or `logger.debug()`" and shows `logger.error("...", error: error)`; the project's logger is `AppLog.shared.<category>(_:level:)` (`Managers/AppLog.swift:298-334`), there is no `logger` and no `error:` label, and the plan's hygiene snapshot treats Swift `print` as a defect. `CLAUDE.md:477-486` ("emoji prefixes for filtering": 📁 🗄️ 💬 ...) matches zero lines of code (grep: 0 occurrences); filtering is by `AppLog` category. "CI expectations: builds cleanly, tests pass" / "Automated checks must pass": there is no `.github/` or other CI (plan §0). `AGENTS.md`'s 4-place pbxproj rule is accurate (verified on `NativeDocumentExtractor.swift` and `DocumentExporter.swift`: PBXBuildFile, PBXFileReference, group child, Sources phase; `objectVersion = 56`, no synchronized groups), so leave it.
- **Fix**: Delete the Legacy sections and `cd legacy/...` line; replace the logging examples with `AppLog.shared.database("...", level: .error)`; replace CLAUDE.md emoji list with the `AppLog` categories (`database, documents, networking, ai, healthData, fileManagement, settings, mlx, ui, general`); change "CI expectations" to "Before opening a PR: build both destinations, tests pass, `swiftlint` at baseline".
- **Blast radius**: agents following debug instructions; dead-link noise.
- **Verification**: grep docs for `legacy/`, `logger.`.

### WS-16-15 — Housekeeping: `.claude/CLAUDE.md` is tracked as lowercase and empty; `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` referenced but absent; CLAUDE.md lists UI suites that never compile; `PRE-BETA-REVIEW.md` has no status header
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `git ls-files` -> `.claude/claude.md` (one line: `# Project-Specific Instructions`); `CLAUDE.md:511` and the WS-16 prompt scope list `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` (not in `git ls-files`, not on disk); `CLAUDE.md:390-393` (ChatInterfaceUITests, DocumentManagementUITests, AccessibilityUITests); `PRE-BETA-REVIEW.md:1`
- **Scenario**: (a) On a case-sensitive checkout, Claude Code looks for `.claude/CLAUDE.md` and will not find the tracked `claude.md`; today it is empty so nothing is lost, but any rule later added there is silently ignored. (b) A dead link in the "Documentation Files" list sends agents looking for a document describing the pipeline. (c) Those three UI suites and four others are not in the UI test target (`grep "in Sources"` in `project.pbxproj`: only `RegressionSmokeUITests` is compiled, 2 tests; TRACKER item 25 / decision 4). CLAUDE.md presents them as the UI test suite. The 5 unit suites it lists are all compiled. (d) `PRE-BETA-REVIEW.md` opens "Verdict: Not beta-ready yet. 2 P0 and 17 unique P1" with no note that the plan marks it fixed (2026-08-30) and WS-01 re-verified it, so it reads as the current verdict.
- **Fix**: (a) `git mv .claude/claude.md .claude/CLAUDE.md` in Phase 5 (or delete; it carries no content). (b) Remove `CLAUDE.md:511` or restore the file. (c) Replace `:390-393` with "UI tests: only `RegressionSmokeUITests.swift` is in the target; the other UI suites are orphaned (TRACKER item 25)". (d) Insert at the top of `PRE-BETA-REVIEW.md` (do not delete): "> **Status (2026-10-24): historical.** Point-in-time review of 2026-08-30. Findings were fixed 2026-08-30 and re-verified by `Documentation/Review/findings/WS-01-prior-findings.md`. The current worklist is `Documentation/Review/TRACKER.md`. The verdict below is not the current verdict."
- **Blast radius**: none functional.
- **Verification**: `git ls-files .claude`; `ls MEDICAL_DOCUMENTS_IMPLEMENTATION.md`.

## Claim verification table

| # | Claim | Where | Actual | Verdict |
|---|---|---|---|---|
| 1 | DB version 10 | CLAUDE.md:10 | 13 (`DatabaseManager.swift:47`) | stale |
| 2 | DB version 12 | CLAUDE.md:111,529; plan §0 | 13 | stale |
| 3 | Example `= 11 // Was 10`, `private static` | CLAUDE.md:127,313 | next is 14; declaration is `internal static` | stale |
| 4 | iPad build `iPad Pro 11-inch (M5),OS=26.5` | CLAUDE.md:104 | exists | true |
| 5 | iPad tests `iPad Pro 11-inch (M4)` | CLAUDE.md:404,460 | no such simulator; command errors | wrong |
| 6 | iPhone 17 Pro destination | CLAUDE/README/AGENTS | exists (26.5) | true |
| 7 | Test commands run from repo root | CLAUDE.md:399, AGENTS.md:19, README:290 | fail: no project at root; need `cd HealthApp` | wrong |
| 8 | Build commands (`cd HealthApp`, `-project`) | CLAUDE.md:96-105 | resolve | true (M5/iPhone) |
| 9 | `swiftlint lint` after `cd HealthApp` | AGENTS.md:61 | `.swiftlint.yml` is in `HealthApp/` | true |
| 10 | Swift 6, iOS 26.0+, universal | CLAUDE/README | per plan §0 / project | true (not re-read from pbxproj) |
| 11 | pbxproj needs 4 entries | AGENTS.md:28-34 | PBXBuildFile, PBXFileReference, group, Sources phase; objectVersion 56 | true |
| 12 | `NativeDocumentExtractor`, `DocumentProcessor`, `MedicalDocumentExtractor`, `MLXOnDeviceClient`, `BedrockClient`, `OpenAICompatibleClient` exist | CLAUDE tables | all exist | true |
| 13 | `HealthDataManager.loadBloodTests()` | CLAUDE.md:258 | absent | wrong |
| 14 | `savePersonalInfo`, `loadConversations`, `importDocument`, `processDocument`, `saveSettings`, `loadSettings`, `loadPreps`, `prefillMedications` | CLAUDE.md:258-262 | exist (`generate(for:)`, `sendMessage(_:useStreaming:)` differ in signature) | true / partly |
| 15 | `AIProviderInterface` shape | CLAUDE.md:62-65 | different | wrong |
| 16 | `AIProvider` / `getAIClient()` in AIChatManager | CLAUDE.md:339-349 | in SettingsManager | wrong |
| 17 | Bedrock: Claude Sonnet 4 | CLAUDE.md:367 | Sonnet 4.5 + Nova Premier | stale |
| 18 | Formats include DOCX | CLAUDE.md:374 | picker is PDF+image only | wrong |
| 19 | `compactChatRules` in `MLXOnDeviceClient.swift`, title generation excluded | CLAUDE.md:363 | exists (`:693,704`); exclusion not re-traced | true / unverified |
| 20 | Key tables list | CLAUDE.md:278-283 | missing `appointment_preps`, `pending_import_reviews` | incomplete |
| 21 | DB extension list | CLAUDE.md:285-290 | missing `+AppointmentPrep`, `+Recovery` | incomplete |
| 22 | Downgrade refused via `incompatibleVersion`, `initializationError`, `DatabaseUnavailableView` | CLAUDE.md:140-144 | all three exist (`DatabaseManager.swift:29,433`; `HealthAppApp.swift:34`) | true |
| 23 | `health_data.sqlite.backup.[timestamp]` for recovery | CLAUDE.md:466 | created before migration, deleted after success; exists only after a failed migration, holds pre-v11 plaintext | misleading |
| 24 | Encryption of all health data | CLAUDE.md:419, README:192,320, Policy:23 | thumbnails, tags, filenames plaintext | wrong (WS-16-02) |
| 25 | No iCloud backup / all data on-device | CLAUDE.md:13,422 | key syncs via iCloud Keychain; DB in device backups; cloud AI | wrong (WS-16-03) |
| 26 | TLS 1.2+ only | CLAUDE.md:423, AGENTS:56 | cleartext HTTP to LAN allowed | wrong (WS-16-11) |
| 27 | `.gitignore` list (`*.sqlite`, `Documents/HealthApp/`, `*.p12`, `AuthKey_*.p8`, `.env*`) | CLAUDE.md:426-432 | all present (`.gitignore:106-147`) | true |
| 28 | Debug emoji prefixes | CLAUDE.md:479-486 | 0 occurrences; AppLog categories | stale |
| 29 | Test files `ModelTests`, `DatabaseTests`, `HealthDataManagerTests`, `ServiceClientTests`, `ChatIntegrationTests` | CLAUDE.md:384-388 | exist and compiled | true |
| 30 | UI test files `ChatInterface/DocumentManagement/Accessibility` | CLAUDE.md:391-393 | exist but not in target | misleading |
| 31 | `MEDICAL_DOCUMENTS_IMPLEMENTATION.md` | CLAUDE.md:511 | absent | wrong |
| 32 | Swift Packages "30+" | CLAUDE.md:492 | 36 resolved pins (TRACKER) | true |
| 33 | `Last Updated: 2026-08-22` | CLAUDE.md:534 | file last changed 2026-08-31 (commit 28fe453b); content now older than 12 commits | stale |
| 34 | `legacy/` directory | AGENTS.md, AGENT_CODEBASE | absent | wrong |
| 35 | Privacy manifest / CI | plan §0 | absent / none | true |
| 36 | 124 Swift files, 23 test files | plan §0 | 124 / 23 | true |
| 37 | 12 document categories, 9 personas | README | 12 / 9 | true |
| 38 | Bedrock models and 200k context | README:~172 | models true; context not re-verified | true / unverified |
| 39 | README project-structure file lists | README:~215-280 | every named file exists | true |
| 40 | Default provider on-device for chat and extraction | README | `SettingsManager.swift:111,116` | true |
| 41 | Cloud vision extraction is opt-in | Policy:50 | `cloudVisionExtractionEnabled = false` | true |
| 42 | Chat shows where data goes and asks before first cloud send | README, Policy:27 | commit 8cf5ee97 | true (not run) |
| 43 | Genetics link "asks first" | Policy:35 | `GeneticTestsSection.swift:606-622` confirmationDialog | true |
| 44 | "Analytics setting is a disabled future feature" | Policy:55 | `SettingsView.swift:681` `futurePreferenceRow` | true |
| 45 | Delete data "through the app" | Policy:75 | Reset leaves files | misleading (WS-16-01) |
| 46 | "A backup will be created first" | SettingsView.swift:50 | none made | wrong (WS-16-01) |
| 47 | Loading a model contacts Hugging Face | Policy:33, OnDeviceLLMSettingsView:135 | no (dir-based load) | stale (WS-16-05) |
| 48 | Last updated July 3, 2026 | Policy:11, Terms:16 | text changed 2026-10-23 | stale |
| 49 | `NSHealthUpdateUsageDescription` removed | commit 3c857bbb | only `NSHealthShareUsageDescription` in pbxproj | true |
| 50 | HIPAA stance (no BAA, personal use) | all | consistent everywhere, incl. archive page | true |
| 51 | TRACKER 23/3/6 arithmetic | TRACKER:5 | counts match Status column | true |
| 52 | Plan: "5 `@unchecked Sendable`" | plan §0 | 4 declarations | stale |

## Doc map (proposed single source per fact)

| Fact / rule | Authoritative file | Others should |
|---|---|---|
| Build / test / lint / MLX-typecheck commands, destinations, working directory | `CLAUDE.md` §Build Commands (add MLX + lint) | README, AGENTS, CONTRIBUTING: one line "see CLAUDE.md" |
| Schema version, migration workflow, table list | `CLAUDE.md` §Database, with the number replaced by "see `DatabaseManager.currentDatabaseVersion`" | plan §0 may keep a number but marked "as of <date>" |
| Definition of Done (5 bullets) | `CLAUDE.md` | AGENTS, AGENT_CODEBASE (verbatim copies, currently 3 places) and CONTRIBUTING (absent) point to it |
| Adding files to Xcode (4 pbxproj places) | `AGENTS.md` (accurate) | CLAUDE.md should state it: it is only in AGENTS and AGENT_CODEBASE today, and agents read CLAUDE.md first. Also add the memory note that SourceKit goes noisy after hand-editing pbxproj |
| Privacy / data-egress facts (what leaves the device, what is encrypted, what Reset removes) | `PrivacyPolicyView.swift` (user-facing truth) | README Privacy section and CLAUDE.md Privacy section summarise it; WS-16-02/03 wording |
| Public product description, features, roadmap, setup | `README.md` | -- |
| Coding style, naming, accessibility, iPad rules | `CLAUDE.md` | AGENTS "Coding Style", CONTRIBUTING code samples should be deleted or aligned (NavigationView, file protection) |
| Contribution process, PR template, security contact | `CONTRIBUTING.md` | -- |
| Review process, severity rubric, finding format | `Documentation/Review/BETA-RELEASE-REVIEW-PLAN.md` | -- |
| Live worklist / status | `Documentation/Review/TRACKER.md` | review README must not describe it as empty |
| Prompts directory | `Personas-Prompts/README.md` (still accurate in structure) | -- |
| Historical review | `PRE-BETA-REVIEW.md` (add status header) | -- |

Rules living in only one doc that belong in `CLAUDE.md`: (1) MLX files compile out of simulator builds (TRACKER only); (2) the 4-place pbxproj registration (AGENTS only); (3) "no force-unwrap, 4-space indent, Conventional Commits" are in AGENTS but not CLAUDE.md; (4) "do not change the DB key to `ThisDeviceOnly`" (Keychain.swift comment only); (5) the `AppLog` logging convention (appears in no doc correctly); (6) CLAUDE.md "DON'T: Build without explicit user request" (`:248`) conflicts with its own Definition of Done ("Run focused tests") and with AGENTS "Use the build and test commands above to verify": pick one (suggest: "build when verifying your own change; do not build speculatively").

## Not verified (explicitly)

- That the documented `generic/platform=iOS` MLX typecheck command succeeds (not run).
- That an upgraded install with a device-only key still opens after the key-sync change (TRACKER says owner-only check outstanding); the Privacy Policy sentence "a restored device could read its own data" depends on it.
- Offline model load on a real device (the code path is simulator-excluded).
- Whether `security@bisonhealth.ai` is a live mailbox.
- Xcode 26.0 vs the installed SDK (iOS 27 runtimes are installed); README/CONTRIBUTING say "Xcode 26.0 or later".
- Terms of Service substantive claims beyond the date (liability, indemnity) are legal text, not checked against code; its "Data and Availability" paragraph says nothing about backup, key sync or reset.
