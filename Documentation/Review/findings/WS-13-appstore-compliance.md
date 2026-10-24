# WS-13 — App Store compliance & metadata

- **Agent / model**: Claude (Sonnet 5.5), subagent run for WS-13
- **Date**: 2026-10-24
- **Commit reviewed**: f95cf804 (working tree clean at start)
- **Scope actually covered**: `HealthApp.entitlements`; `Info.plist` and every `INFOPLIST_KEY_*` / signing / deployment setting in `project.pbxproj`; `Assets.xcassets` (both icon sets, 1024 px pixel data decoded); `PrivacyPolicyView`, `TermsOfServiceView`, `FirstLaunchDisclaimerView` (read in full); `Models/Doctor.swift`; `Services/AIProviderInterface.swift` (`HealthChatRules`), `BedrockClient`/`OpenAICompatibleClient` prompt assembly; `ChatDetailView` consent and disclaimer paths; `AppointmentPrepManager`; `HealthKitManager` (authorization and type list); `HealthAppApp` launch sync; `SettingsView` reset flow and `DatabaseManager.resetDatabase`; `Keychain.swift`; `FileSystemManager` storage/thumbnails; `MLXModelDownloadManager` file filter and revision; grep of all Swift sources for required-reason APIs; SPM checkouts in DerivedData for privacy manifests and API use; `nm -u` of the existing Debug-iphoneos binary; WS-07 and WS-12 findings (cross-referenced, not repeated).
- **Scope not covered**: no simulator was booted and no app was run (instructed). No Release/archive build, so no Xcode "Generate Privacy Report" and no check of what an archive signs. No model was run, so what the AI says to "should I stop my blood-pressure medication?" is **predicted from the prompts, not observed**. App Store Connect itself (metadata, URLs, screenshots, age-rating answers, existing privacy answers) is not visible from the repo; those rows are marked UNVERIFIED. Apple pages that render client-side returned no body text to the fetch tool; where that happened I say so and do not cite the page.
- **Verdict**: **Not submission-ready.** One certain upload blocker (no privacy manifest), four likely-rejection or honest-claims problems (physician personas that suppress disclaimers, an unconsented cloud path, inaccurate and incomplete privacy policy, a reset that does not delete files). TestFlight internal builds will upload only after the manifest exists; external beta needs the policy fixed first.
- **Counts**: P0=1 P1=4 P2=8 P3=1 (dropped: 0)

## Sources fetched (all retrieved 2026-10-24)

| Short name | URL | What was obtained |
|---|---|---|
| ARG | https://developer.apple.com/app-store/review/guidelines/ | Text of 1.4.1, 2.1, 2.3.1, 2.5.2, 4.2, 4.7, 5.1.1, 5.1.2(i), 5.1.3. Fetch tool truncated after 5.2.5 (14 KB unread, past the sections used). The page shows no "last updated" date. |
| RRAPI | https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api (via Apple's `tutorials/data/...json` mirror) and `.../nsprivacyaccessedapitypereasons` | Policy text and reason-code descriptions. The JSON strips the code identifiers (C617.1 etc.); I matched descriptions to codes by order and prior knowledge, so **the code strings themselves are not quoted from Apple**. |
| ENC | https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations (JSON mirror) | Text on `ITSAppUsesNonExemptEncryption`. |
| PRIV | https://developer.apple.com/app-store/app-privacy-details/ | Definition of "collect", on-device processing, tracking. |
| SDKS | https://developer.apple.com/support/third-party-SDK-requirements/ | List of SDKs needing manifests. |
| SHOT | https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications | Required sizes. |
| AGE | https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/ | Age-rating tiers and definitions (first 100 KB of 116 KB). |
| MEDDEV | https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status | Regulated-medical-device declaration. |
| NOT FETCHABLE | `privacy-manifest-files` doc page, `add-an-app-icon` help page, the export-compliance exemption decision page | Returned title only or no relevant text. Nothing below is cited to them. |

---

## Findings

### WS-13-01 — No `PrivacyInfo.xcprivacy`; the app uses required-reason APIs
- **Severity**: P0 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: project-wide (file absent); `Managers/HealthKitManager.swift:14` (UserDefaults), `Managers/AppLog.swift:679-736`, `Utils/FileSystemManager.swift:462-550`, `Utils/DocumentImporter.swift:378` (file timestamps)
- **Scenario**: Archive and upload to App Store Connect / TestFlight. The app writes `UserDefaults` in 12 files (60 call sites; plus `@AppStorage` in 3 views) and reads `creationDate`/`contentModificationDate`/`attributesOfItem` in 5 files. No manifest declares either category, so the upload is flagged and not accepted.
- **Evidence**: RRAPI (2026-10-24): "Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect." Repo: `find .. -name '*.xcprivacy'` returns nothing. `nm -u` on the Debug-iphoneos binary shows imports `_stat`, `_fstat`, `_lstat` (File timestamp category; caller not identified, probably an SDK); it shows no `mach_absolute_time`, no `statfs`/`getattrlist`. No disk-space or active-keyboard APIs appear in app source.
  ```swift
  // Managers/HealthKitManager.swift:14
  UserDefaults.standard.set(isAuthorized, forKey: "healthKitIsAuthorized")
  // Utils/FileSystemManager.swift:471-474
  let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
  if let modificationDate = resourceValues.contentModificationDate, modificationDate < cutoffDate {
  ```
- **Fix**: add the manifest in "Proposed PrivacyInfo.xcprivacy" below to the app target (hand-register in `project.pbxproj`, 4 places, per the repo's memory note). Then archive and run Xcode's Product > Generate Privacy Report to confirm the aggregate.
- **Blast radius**: build/upload only; no runtime behaviour. Unverified: which linked SDK imports `stat`/`fstat`/`lstat` (a Release-archive `nm` plus the privacy report settles it).
- **Verification**: upload a build to TestFlight with no "missing API declaration" email; the generated privacy report lists the two categories with no SDK flagged.

### WS-13-02 — Physician personas claim credentials and are told to suppress "see a doctor" and disclaimers
- **Severity**: P1 · **Confidence**: CONFIRMED that the prompts say this; PLAUSIBLE that a reviewer sees it (unverified link: what the model actually outputs, not run) · **Effort**: M
- **Location**: `Models/Doctor.swift:36,51-52,66,25` (also repeated at 91-92 for each persona and the compact prompts)
- **Scenario**: Reviewer selects the default "Primary Care Physician" and asks "should I stop taking my blood-pressure medication?". The system prompt says the model is a "board-certified Primary Care Physician", asks for "Pragmatic recommendations", and forbids "see a doctor" reminders and disclaimers. The shared `HealthChatRules` (appended on all three providers: `BedrockClient.swift:259,363`, `OpenAICompatibleClient.swift:619-621`, MLX `compactChatRules`) says "Do not invent, diagnose, or tell the user to start, stop, substitute, or change a medicine or dose." The two instruction sets conflict; the likely output is a refusal with no pointer to a clinician, or a recommendation that breaks the rule. Which one is unobserved.
- **Evidence**:
  ```swift
  // Doctor.swift
  36: Role: You are a board-certified Primary Care Physician. Provide clinical guidance ...
  51: • Do not add unsolicited information or "see a doctor" reminders
  52: • No meta-commentary, disclaimers, or AI disclosure statements
  66: 2. Clinical Analysis: ... → Pragmatic recommendations (max 3000 chars)
  ```
  ARG 1.4.1 (2026-10-24): "Apps should remind users to check with a doctor in addition to using the app and before making medical decisions." and "Medical apps that could provide inaccurate data or information, or that could be used for diagnosing or treating patients may be reviewed with greater scrutiny." The personas also assert "20+ years" experience and licences (`Doctor.swift:76,219,289`), which conflicts with the Terms ("not a healthcare service", "does not provide ... diagnosis").
- **Fix**: rewrite personas as "information assistants with a [specialty] focus", drop credential claims, delete the "no see-a-doctor / no disclaimers / no AI disclosure" lines, and add a rule that medication or dose questions get "discuss with your prescriber". Confirm with a scripted run on each provider.
- **Blast radius**: all chat, appointment-prep generation (uses the same prompts), the on-device compact prompts (their token budget is tight, per `MLXContextBudget`), prompt tests.
- **Verification**: scripted turn "should I stop my blood-pressure medication?" on Bedrock, an OpenAI-compatible stub, and MLX returns a clinician referral and no start/stop advice.

### WS-13-03 — Cloud AI is used by Appointment Prep with no disclosure or consent
- **Severity**: P1 · **Confidence**: CONFIRMED by code trace (not run) · **Effort**: S
- **Location**: `Managers/AppointmentPrepManager.swift:150-157`; the only consent is `Views/ChatDetailView.swift:22,272`
- **Scenario**: User configures Bedrock for chat and taps "Generate" in Appointment Prep. `generate` calls `settingsManager.getAIClient()`, which returns the Bedrock client, and sends symptoms, notes, medications and `buildHealthContext(...)` three times. The "Send to Bedrock?" dialog and `hasAcknowledgedCloudProcessing` exist only in `ChatDetailView`. `grep hasAcknowledgedCloudProcessing` finds no other use. The privacy policy says "The chat screen shows which provider is in use before you send, and asks you once" — true of chat only.
- **Evidence**:
  ```swift
  let client = settingsManager.getAIClient()
  let healthContext = await buildHealthContext(selectedTypes: prep.includedHealthDataTypes)
  ...
  let timelineRaw = try await client.sendMessage(composeMessage(...), context: healthContext).content
  ```
  ARG 5.1.2(i) (2026-10-24): "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so."
- **Fix**: move the acknowledgement into a shared helper used by chat, appointment prep, and cloud document extraction, and make the dialog name the provider and the data categories. Also reconsider a permanent "don't ask again" (see structural risks).
- **Blast radius**: `AppointmentPrepView`, any caller of `getAIClient()`; the cloud-extraction path in `DocumentProcessor` (default off, `SettingsManager.swift:872`, not traced further here).
- **Verification**: with Bedrock selected and acknowledgement cleared, Appointment Prep shows the dialog and sends nothing until accepted.

### WS-13-04 — Privacy Policy and Terms: inaccurate claims, enumerated
- **Severity**: P1 · **Confidence**: CONFIRMED for each row (code traced, not run) · **Effort**: S
- **Location**: `Views/PrivacyPolicyView.swift:23,27,33,75`; `Views/TermsOfServiceView.swift:27,57`
- **Scenario**: A tester or reviewer compares the policy with behaviour. Each row below is a statement a reader can falsify.

| # | Line | Claim | What the code does | Direction |
|---|---|---|---|---|
| 1 | Privacy:23 | "The app encrypts health data, documents, chats, and appointment prep records." | Chats, DB filenames, document files are encrypted. **Page-1 thumbnails are written as plaintext JPEG/PNG** (`FileSystemManager.swift:240-266` `thumbnailData.write(to:)`, in `Documents/Thumbnails`, which is backed up). **Free-text tags are plaintext** (`DatabaseManager+Documents.swift:51` `documentTags <- tagsString`). **On-disk imported-file names embed the original filename** (`FileSystemManager.swift:131-136` `"\(UUID())_\(sanitizedFileName)"`), so "Smith_lipid_panel.pdf" is readable in a backup. Tracker 21 (rest). | Overclaims |
| 2 | Privacy:33 | "Downloading an on-device model, **and loading one**, contacts Hugging Face" | Load no longer does (commit 330bebf9, `MLXOnDeviceClient.swift:552-575` loads from a local directory). | Stale, harmless but wrong |
| 3 | Privacy:27 | Chat "asks you once before the first such message" (implying cloud sends are gated) | Appointment Prep is not gated (WS-13-03). Also the dialog is permanent after one tap. | Incomplete |
| 4 | Privacy:75 | "you can view, edit, export, or delete it through the app" | "Reset Database" removes DB rows only; imported files and thumbnails stay on disk (WS-13-05). | Overclaims |
| 5 | Privacy (absent) | No mention of **Apple Health**. The app requests read access to heart rate, blood pressure, temperature, SpO2, respiratory rate, weight, height, sleep, DOB, sex, blood type (`HealthKitManager.swift:41-87`), stores it, and may include it in AI context. | Omission. 5.1.3 covers HealthKit data; the policy never says what is read or that it can reach a cloud provider. | Omission |
| 6 | Privacy (absent) | No mention of the camera/photo import, local-network AI servers, or MetricKit diagnostics kept on device (`AppLog.swift:156`, `isExcludedFromBackup`). | Omission, low risk | Omission |
| 7 | Privacy:17 | "does not collect ... crash reports, ... device identifiers" | Accurate for the developer: MetricKit payloads are written to a local file and shared only by the user (`AppLog.swift:853`). Apple's own TestFlight/App Store crash sharing is not under the app's control. | OK, but say "the app does not transmit" |
| 8 | Terms:27 | "is not a ... medical device" | Fine as a statement, but must match the App Store Connect "regulated medical device" answer (WS-13-10). | Consistency |
| 9 | Terms:57 | "provided as a local personal tool" | The app has a cloud mode and the key syncs via iCloud Keychain (Privacy:29). | Minor |
| 10 | README/CLAUDE.md vs Privacy:31 | CLAUDE.md says "Backup: On-device only (iCloud/CloudKit backup removed)". Policy says the encrypted DB **is** in device backups and the key syncs through iCloud Keychain. | Policy is the accurate one (`Keychain.swift:73-80`, DB in Application Support and files in Documents with only logs and migration backups excluded). Docs are wrong; see structural risks. | Internal contradiction |

- **Evidence**:
  ```swift
  // PrivacyPolicyView.swift:23
  ... The app encrypts health data, documents, chats, and appointment prep records. The app does not sync your records through CloudKit.
  // FileSystemManager.swift:263-266
  guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else { throw ... }
  try thumbnailData.write(to: thumbnailURL)
  ```
  ARG 5.1.1 (2026-10-24): "Explain its data retention/deletion policies and describe how a user can revoke consent and/or request deletion of the user's data."
- **Fix**: rows 1-5 as above; either encrypt thumbnails/tags/filenames (tracker 21) or reword line 23 to "document contents and chat text are encrypted; thumbnails and file names are not". Add an Apple Health section. Bump "Last updated" (both files say July 3, 2026).
- **Blast radius**: copy also appears in `FirstLaunchDisclaimerView.swift:153` ("Health data, documents, chats, and appointment prep records are encrypted") and README.
- **Verification**: re-read each row against code after the change; a test that asserts no `.jpg/.png` in `Thumbnails` is readable without the key, if thumbnails are encrypted.

### WS-13-05 — "Reset Database" leaves documents and thumbnails on disk while promising permanent deletion
- **Severity**: P1 · **Confidence**: CONFIRMED by trace (not run) · **Effort**: M
- **Location**: `Views/SettingsView.swift:48,1010-1031`; `Database/DatabaseManager.swift:776-806`; `Managers/DocumentManager.swift:512` (no callers)
- **Scenario**: User imports a lab PDF, taps Settings > Reset Database, sees "All health data has been permanently deleted". `resetDatabase()` deletes the SQLite file, WAL/SHM and migration backups, nothing else. `Documents/Imported/<uuid>_<name>.pdf` (encrypted) and `Documents/Thumbnails/*` (plaintext page-1 image) remain. `DocumentManager.cleanupOrphanedFiles()` is the only orphan sweeper and has zero callers. The encryption key also stays in the keychain, so the encrypted files stay decryptable. The confirmation text also says "A backup will be created first", which is false now (no backup is made; migration backups are deliberately deleted).
- **Evidence**:
  ```swift
  case .database: return "⚠️ WARNING: This will permanently delete ALL your health data, documents, and chat history. ... A backup will be created first."
  ```
  ARG 5.1.1 text as in WS-13-04.
- **Fix**: after a successful DB reset, also remove `Documents/Imported`, `Documents/Thumbnails` (call `FileSystemManager` from the reset path), and reword the dialog. Decide whether the keychain key should be rotated.
- **Blast radius**: `DatabaseUnavailableView` offers the same reset (`resetDatabase` comment), so a user recovering from a failed open also orphans files. Overlaps WS-02/WS-07.
- **Verification**: import a document, reset, and assert both directories are empty and the dialog text has no "backup".

### WS-13-06 — Export compliance key absent
- **Severity**: P2 · **Confidence**: CONFIRMED (key absent); the correct value is a legal call I could not settle · **Effort**: S
- **Location**: `Info.plist` and `INFOPLIST_KEY_*` in `project.pbxproj:1094-1105` (no `ITSAppUsesNonExemptEncryption`)
- **Scenario**: Every TestFlight/App Store upload stops at the export-compliance questionnaire until answered, and external TestFlight cannot proceed until it is.
- **Evidence**: ENC (2026-10-24): "Set the value to [NO] if your app—including any third-party libraries it links against—doesn't use encryption, or if it only uses forms of encryption that are exempt from export compliance documentation requirements." and "the use of encryption that's built into the operating system—for example, when your app makes HTTPS connections using [URLSession]—is exempt ... whereas the use of proprietary encryption is not."
- **What the app uses**: CryptoKit AES-GCM for data at rest (`DatabaseManager.swift:970-1016`, `FileSystemManager.swift:613`); URLSession HTTPS; and **bundled non-OS crypto** (swift-crypto's CCryptoBoringSSL, swift-nio-ssl's BoringSSL, aws-crt-swift) via the AWS SDK. All are standard algorithms, none proprietary.
- **Fix**: owner decision. The usual route is `ITSAppUsesNonExemptEncryption = NO` with the standard-algorithms exemption, then keep the year-end self-classification report in mind (ENC says it may be required for exempt use). I did not fetch Apple's exemption decision page (it returned no body), so I am not asserting which exemption number applies.
- **Blast radius**: build settings only.
- **Verification**: the upload no longer prompts.

### WS-13-07 — `aps-environment` entitlement with no push code
- **Severity**: P2 · **Confidence**: CONFIRMED (no push usage) · **Effort**: S
- **Location**: `HealthApp/HealthApp.entitlements`
- **Scenario**: `grep -riE "push|APNs|registerForRemote|UNUserNotificationCenter|UIBackgroundModes"` finds no push code, no background mode, no notification permission. The entitlement forces automatic signing to need the Push Notifications capability on the App ID, and ships an unused capability in a health app.
- **Evidence**: `<key>aps-environment</key><string>development</string>`. (The only "push" hits are English comments.)
- **Fix**: delete the key, and drop the capability in the Developer portal.
- **Blast radius**: signing only.
- **Verification**: archive signs; `codesign -d --entitlements :-` has no `aps-environment`.

### WS-13-08 — HealthKit usage string and launch-time prompt
- **Severity**: P2 · **Confidence**: CONFIRMED for the string and trigger; PLAUSIBLE that review objects (unverified: reviewer reaction) · **Effort**: S
- **Location**: `project.pbxproj:1098`; `HealthAppApp.swift:285-300`; `Managers/HealthDataManager.swift:630-631`
- **Scenario**: After accepting the disclaimer, the launch task calls `syncFromAppleHealth()`, which calls `requestAuthorization` if not authorized, so the Health permission sheet appears before the user has chosen to use Health. The string says data goes "with the AI doctor for better health recommendations", but (a) the app reads and stores it locally and sends it to an AI provider only if included in context, and to a cloud provider only if one is configured, (b) the string omits date of birth, sex, and blood type, which the app also requests (`HealthKitManager.swift:81-87`), and (c) "AI doctor ... recommendations" contradicts the not-medical-advice position.
- **Evidence**:
  ```
  INFOPLIST_KEY_NSHealthShareUsageDescription = "BisonHealth needs access to your health data to provide personalized health insights and sync your vitals, sleep data, and other health metrics with the AI doctor for better health recommendations."
  ```
  Entitlements and write path: `requestAuthorization(toShare: [], read: allTypes)` (`HealthKitManager.swift:151`), no `HKHealthStore.save`, so no write string is needed and the removed `NSHealthUpdateUsageDescription` is correct. `com.apple.developer.healthkit.access` as an empty array is correct for an app that reads no Health Records (clinical documents) data. ARG 5.1.3(ii) "must not write false or inaccurate data into HealthKit": not applicable, nothing is written.
- **Fix**: reword the string ("Reads vitals, sleep and basic profile from Apple Health to show them in your records. Included in AI chat only when you choose, and sent off-device only if you use a cloud provider."), and move the first sync behind an explicit "Connect Apple Health" button.
- **Blast radius**: first-run flow, `HealthAppApp` startup task, UI tests that disable HealthKit.
- **Verification**: fresh install shows no Health sheet until the button is tapped.

### WS-13-09 — Medical disclaimer is gated at first launch but nearly absent in-session
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/ChatEmptyStateView.swift:58-63`; `Views/ChatDetailView.swift` (no disclaimer text; `grep` for disclaimer/medical advice finds none)
- **Scenario**: Acceptance gates the app (`HealthAppApp.swift:64`, default shows the disclaimer on DB error). Once a conversation is open, nothing on screen says the replies are AI-generated or non-medical; the only line is `caption2` secondary text on the empty state, which disappears after the first message. Appointment-prep output has none either.
- **Evidence**:
  ```swift
  Text("AI chat is for personal health insights only. Not for professional medical advice.")
      .font(.caption2).foregroundColor(.secondary)
  ```
  ARG 1.4.1 reminder sentence quoted in WS-13-02.
- **Fix**: a persistent one-line footer in the chat composer and on prep output ("AI-generated, not medical advice. Check with your doctor before medical decisions.").
- **Blast radius**: chat layout on iPhone/iPad; UI-test snapshots.
- **Verification**: footer visible in an active conversation at the largest Dynamic Type size.

### WS-13-10 — App Store Connect declarations the metadata must make
- **Severity**: P2 · **Confidence**: CONFIRMED that the declarations apply; answers UNVERIFIED (not visible from repo) · **Effort**: S
- **Location**: `project.pbxproj:1095` (`LSApplicationCategoryType = public.app-category.healthcare-fitness`)
- **Scenario**: With a Health & Fitness category and the AI answering medication questions, three declarations bite. (a) **Regulated medical device**: MEDDEV (2026-10-24): apps in the EU/EEA, UK or US "that also meet either" criterion, "primary or secondary category of Health & Fitness or Medical" or "frequent" for Medical or Treatment Information, must declare yes or no. Answer **No** is consistent with the Terms, but it must be a deliberate answer. (b) **Age rating**: AGE (2026-10-24) defines Medical or Treatment Information as "Content that provides diagnoses or guidance around the management of medical conditions or health and wellness. May include: medication guidance ..." and places frequent medical or treatment information at 16+, infrequent at 13+. An AI that discusses medications on request is at least "infrequent"; answering "none" invites a rating mismatch. (c) **Category**: healthcare-fitness vs Medical: Health & Fitness is the lower-scrutiny and correct choice for a records organiser; Medical would invite 1.4.1 scrutiny.
- **Fix**: owner answers in ASC; see drafts below.
- **Blast radius**: metadata only.
- **Verification**: the three screens show the intended answers.

### WS-13-11 — Downloaded model files: unpinned `main`, no hash check, interpreted templates
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified: how Apple weighs data-only templates; no observed rejection) · **Effort**: M
- **Location**: `MLXOnDeviceLLM/MLXModelDownloadManager.swift:632,671,877-879`; `Package.resolved` (swift-jinja 2.3.5)
- **Scenario**: The app lists a Hub repo at `revision: "main"` and downloads every `.safetensors`, `.json` and `.jinja` file, trusting only the reported size. The repos include one under `bisonnetworking/` and two third-party (`mlx-community/`). Anyone with write access to those repos can change a chat template or weights after App Review, changing how a health assistant behaves without an app update. Weights are data. The chat template is a Jinja program interpreted by swift-jinja; it can reshape every prompt, including dropping the safety rules from the rendered conversation.
- **Evidence**:
  ```swift
  let entries = try await Self.realtimeHubClient.listFiles(in: repository, kind: .model, revision: "main", recursive: true)
  ...
  if path.hasSuffix(".safetensors") || path.hasSuffix(".json") || path.hasSuffix(".jinja") { return true }
  ```
  ARG 2.5.2 (2026-10-24): "nor may they download, install, or execute code which introduces or changes features or functionality of the app". Weights and sandboxed templates are arguably not "code", but "changes features or functionality" is the clause a reviewer would cite.
- **Fix**: pin each catalog entry to a commit SHA and verify the per-file SHA-256 the Hub reports (exact field in the `swift-huggingface` TreeEntry API not checked: fix: verify the API before coding). State in review notes that templates are data. Cross-reference WS-12-11.
- **Blast radius**: all three catalog models; the download retry budget; model cache validity check.
- **Verification**: a tampered file of equal size is rejected.

### WS-13-12 — Icon 1024 px has an alpha channel; second icon set unused
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified: whether the current toolchain strips it at build; I could not fetch Apple's icon rule) · **Effort**: S
- **Location**: `Assets.xcassets/AppIcon-BisonHealthAI-Pro.appiconset/AppIcon-BisonHealthAI-Pro-1024.png`
- **Scenario**: The marketing icon is RGBA (PNG colour type 6). I decoded every pixel: minimum alpha is 255, so it is visually opaque, but the channel is present. Apple has historically rejected an alpha channel in the large icon; SHOT (2026-10-24) states the same for screenshots ("Images can't include alpha channels or transparencies") but I could not retrieve the icon-specific rule, so this is carried from memory and unconfirmed.
- **Evidence**: `file`: "PNG image data, 1024 x 1024, 8-bit/color RGBA". All 15 sizes in the set are present. `AppIcon-Doctor-Dark` (also RGBA, opaque) is not referenced by `ASSETCATALOG_COMPILER_APPICON_NAME` or any alternate-icon setting or code.
- **Fix**: re-export the 1024 icon without alpha (`sips -s format png` is not enough; flatten onto the background colour). Delete `AppIcon-Doctor-Dark` or wire it as an alternate icon deliberately (and its "Doctor" name conflicts with WS-13-02).
- **Blast radius**: asset catalog only.
- **Verification**: `file` shows RGB; archive validation passes.

### WS-13-13 — No public privacy-policy/support URLs or review demo path
- **Severity**: P2 · **Confidence**: PLAUSIBLE (unverified: ASC fields may already be filled; nothing in the repo shows a URL) · **Effort**: M
- **Location**: `Views/SettingsView.swift:788,792` (in-app only); `README.md:364` (GitHub issues URL only)
- **Scenario**: ARG 5.1.1 (2026-10-24): "All apps must include a link to their privacy policy in the App Store Connect metadata field and within the app in an easily accessible manner." In-app is satisfied. The only reachable address in the repo is `support@bisonnetworking.com` and a GitHub issues page; no hosted policy. For review, a fresh install is empty: chat needs a 2.15 GB model download or cloud credentials, and the seeded demo data (`HealthAppApp.swift:480-538`) exists only under `--ui-testing` launch arguments, which a reviewer cannot set. ARG 2.1 (2026-10-24) asks for "demo account info" or "a built-in demo mode ... with prior approval"; the app has no login, so the equivalent is review notes plus the sample documents.
- **Fix**: host the policy at a stable URL and mirror the in-app text; prepare a sample lab PDF for the reviewer; use the reviewer notes below.
- **Blast radius**: metadata only.
- **Verification**: URL opens logged out; a reviewer can reach a populated record in under two minutes.

### WS-13-14 — iOS 26.0 minimum is deliberate-looking; confirm
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `project.pbxproj` `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- **Scenario**: Business decision, not a defect. Every TestFlight tester needs iOS 26; the addressable audience is whoever has updated. Nothing in the code needs 26 specifically that I checked, so the choice is the owner's. CLAUDE.md states it as the target.
- **Fix**: none required; record the decision.

### Dropped / not raised
None dropped; 14 findings (limit 15). Items checked and found fine: no accounts or sign-in anywhere (`grep` for sign in/up, ASAuthorization finds only a help string telling users to sign up for AWS), so account-deletion requirements do not apply; the app should still keep the local deletion path honest (WS-13-05). No analytics/tracking SDKs, no IDFV/IDFA, no ATT, no CloudKit. `NSAllowsLocalNetworking` is the narrow ATS exception. The `kernel.increased-memory-limit` entitlement is a standard capability.

---

## Compliance checklist

| Item | Requirement (source, fetched 2026-10-24) | Current state | Gap | Sev |
|---|---|---|---|---|
| Privacy manifest | RRAPI: required-reason use must be declared or the app "isn't accepted by App Store Connect" | Absent | Add manifest (WS-13-01) | P0 |
| SDK manifests | SDKS: listed SDKs need manifest + signature when added; any version | None of the app's SDKs is on the list by name. Manifests present: aws-sdk-swift (AWSClientRuntime), smithy-swift ClientRuntime, aws-crt-swift, SQLite.swift, swift-crypto (all targets), swift-nio (NIOPosix, NIOFS, _NIOFileSystem), swift-nio-ssl. **Absent**: mlx-swift, mlx-swift-lm, swift-transformers, swift-huggingface, swift-jinja, textual (your fork), async-http-client, EventSource, swiftui-math, yyjson | Source scan shows API use only in swift-huggingface (`HubClient+Files.swift:1737` `attributesOfItem`) and textual (`Logger.swift:21` `UserDefaults`). The app-level manifest below covers both. A manifest for the textual fork is your responsibility (P3, optional if the app manifest covers it) | P2 |
| Export compliance | ENC: set `ITSAppUsesNonExemptEncryption` | Absent | WS-13-06 | P2 |
| Push entitlement | Not a rule; unused capability | `aps-environment=development`, no push code | Remove (WS-13-07) | P2 |
| HealthKit strings and entitlement | Usage string must describe use; no write string without write | Read-only; no `NSHealthUpdateUsageDescription` (correct); `healthkit.access` empty (correct) | String wording, launch prompt (WS-13-08) | P2 |
| 5.1.3 health data | ARG 5.1.3(i)(ii) quoted above | HealthKit data stored locally, not used for ads; DB is in device backups and the key syncs through iCloud Keychain | See structural risks | P2 |
| Medical (1.4.1) | ARG 1.4.1 | Gate at first launch; weak in-session; personas suppress it | WS-13-02, 09 | P1 |
| AI data sharing (5.1.2(i)) | ARG 5.1.2(i) | Chat gated; Appointment Prep not | WS-13-03 | P1 |
| Privacy policy accuracy and URL | ARG 5.1.1 | In-app only, inaccurate in 5 rows | WS-13-04, 13 | P1 |
| Deletion | ARG 5.1.1 retention/deletion | Reset leaves files | WS-13-05 | P1 |
| Downloaded code (2.5.2) | ARG 2.5.2 | Weights + jinja from unpinned `main` | WS-13-11 | P2 |
| Minimum functionality (4.2) | ARG 4.2 "beyond a repackaged website" | Records, vitals, native OCR import and export work with no model; clearly more than a wrapper | Say so in notes | OK |
| Notes for Review | ARG 2.3.1(a) "described with specificity" | Notes drafted below | Owner to enter | P2 |
| Account deletion | ARG 5.1.1: "If your app supports account creation..." | No accounts | None | OK |
| Icon | (Apple icon page not fetchable) | RGBA, opaque; 15 sizes present | WS-13-12 | P2 |
| Screenshots | SHOT: at least one for "iPhone with Dynamic Island (medium display)" (1179x2556 or 1206x2622) and one iPad 13" (2064x2752 or 2048x2732), up to 10 each, "Images can't include alpha channels" | Not in repo (UNVERIFIED) | Capture on iPhone 17 Pro and iPad Pro 13" (the repo's iPad sim is 11"; use a 13" device or the scaled fallback) | P2 |
| Age rating | AGE: tiers 4+/9+/13+/16+/18+; Medical or Treatment Information frequent = 16+, infrequent = 13+ | UNVERIFIED | Answer deliberately (WS-13-10) | P2 |
| Regulated medical device | MEDDEV | UNVERIFIED | Declare No, deliberately | P2 |
| Category | healthcare-fitness | Set | Confirm intent | P3 |
| Support / marketing URL, name, subtitle, keywords, description, What's New | ARG 2.1(a): placeholders scrubbed | Not in repo (UNVERIFIED) | Owner | P2 |
| Deployment target iOS 26.0 | Business decision | As set | Record (WS-13-14) | P3 |

## Proposed `PrivacyInfo.xcprivacy` (not added to the project)

Reason codes: UserDefaults `CA92.1` (app-only reads and writes; description matched to Apple's "read and write information that is only accessible to the app itself"). File timestamp `C617.1` (own container: log retention, cache cleanup, model cache) and `3B52.1` (files the user picked in the document picker, `DocumentImporter.swift:378`). `DDA9.1` is **not** declared: `AppLog` and `FileSystemManager` use timestamps for retention decisions, not for display (confirm no timestamp is shown in UI before adding it). No Disk space, System boot time or Active keyboard use was found in app source or by symbol scan. The code strings are from my knowledge of Apple's list; RRAPI's JSON mirror dropped the identifiers, so check them against Xcode's manifest editor.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTracking</key>
	<false/>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryUserDefaults</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>CA92.1</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyAccessedAPIType</key>
			<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
			<key>NSPrivacyAccessedAPITypeReasons</key>
			<array>
				<string>C617.1</string>
				<string>3B52.1</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

`NSPrivacyCollectedDataTypes` is empty on the reasoning below (the developer receives nothing); if the owner prefers the conservative answer, add Health and Fitness (`NSPrivacyCollectedDataTypeHealth`), Other User Content, purpose `NSPrivacyCollectedDataTypePurposeAppFunctionality`, Linked false, Tracking false, so the manifest and the ASC labels agree.

## Draft App Store Connect privacy answers

Basis (PRIV, 2026-10-24): "'Collect' refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time", and "Data that is processed only on device is not 'collected'."

- **Recommended: "Data Not Collected."** The developer operates no server and receives nothing. Chat context goes from the user's device to a provider account or server the user owns (AWS Bedrock with the user's own credentials, or a user-run OpenAI-compatible endpoint). The Hugging Face download receives the device IP address and no health data; Hugging Face is not a partner whose code was added to the app. Genetics links send gene and result only after an explicit prompt, to a public reference site (`pharmdog.clinpgx.org`).
- **Tracking**: No. No ATT, no advertising ID, no tracking domains.
- **Judgement call the owner must make**: Apple counts "third-party SDKs ... whose code you've added" as partners. The AWS SDK is such code, and it moves health text to AWS. Whether that is "collection" when AWS is the user's own account is not settled by the text I fetched. If the owner or counsel reads it conservatively, declare: Health (Health & Fitness), Other User Content (chat text); purpose App Functionality; **not** used for tracking; linked-to-user: the data is tied to the user's AWS credentials, so declare Linked. State the cloud case honestly in the policy either way.
- **Contradictions to fix before answering**: WS-13-04 rows 1, 3, 4, 5.

## Draft reviewer notes (App Store Connect "Notes for Review")

```
BisonHealth AI is a personal health-records organiser. There is no account, sign-in, or server; nothing needs a demo login.

Core features work with no setup: add a health profile and vitals, import a document (Documents tab > Import, Scan or Photos; a sample lab report PDF is attached), view extracted lab values, export. Document text is read on-device with PDFKit and Apple Vision.

AI chat is optional and off until configured. It is not a medical device and does not diagnose or advise on medication; it shows a disclaimer at launch and in every conversation.
 - On-device: Settings > On-Device AI > enable > download "MediPhi Instruct" (2.15 GB, Wi-Fi). Files come from huggingface.co and are model weights, tokenizer files and a chat template (data, not executable code). Models are pinned to a fixed revision. Chat then works offline.
 - Cloud (optional, off by default): AWS Bedrock or an OpenAI-compatible server using the user's own credentials. A confirmation names the provider before any health data is sent. No credentials are needed to review.

Apple Health: read-only access to vitals, sleep and basic profile, requested when you tap Connect Apple Health. Nothing is written to Health.
Camera: scans paper documents. Photos: imports document images.
Local network: only if the user points the app at their own AI server on their LAN.

Regulated medical device: No. Age rating answers reflect health information the user supplies and AI-generated health information.
Encryption: standard algorithms only (Apple CryptoKit AES-GCM, HTTPS), no proprietary cryptography.
```
(Statements marked "pinned" and "Connect Apple Health button" and "disclaimer in every conversation" are only true after WS-13-11, 08 and 09 are fixed; edit the notes to match what ships.)

## Structural risks (max 5)
- DB in `Application Support` and imported files in `Documents` are in device backups, and the key is `kSecAttrSynchronizable`. CLAUDE.md and the README still say "on-device only / no iCloud backup", and ARG 5.1.3(ii) says apps "may not store personal health information in iCloud". An iCloud *device backup* is not the same as the app writing to iCloud, and I found no CloudKit use, so I rate this P2 and did not raise it as a finding. Reconcile the docs with `Keychain.swift:73-80`, and consider `isExcludedFromBackup` for HealthKit-derived data as a design decision.
- The cloud-consent dialog is a single permanent `@AppStorage` flag, not tied to provider. Switching from one provider to another, or from a LAN server to Bedrock, does not ask again.
- Personas carry the app's whole medical posture in strings (`Doctor.swift`); there is no test that the rendered system prompt contains the safety rules after persona text, only that the rule text exists.
- The SDK-manifest picture depends on SPM static linking; only an archive plus the privacy report proves what App Store Connect will see.
- Legal copy (policy, terms, disclaimer) is duplicated across three views and the README with no single source, which is how the stale "loading contacts Hugging Face" and "encrypted" lines survived.

## Machine-readable summary
```json
[
  {"id":"WS-13-01","title":"No PrivacyInfo.xcprivacy; UserDefaults and file-timestamp APIs undeclared","severity":"P0","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/HealthKitManager.swift:14","HealthApp/HealthApp/Utils/FileSystemManager.swift:471"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-02","title":"Physician personas claim credentials and suppress see-a-doctor/disclaimers","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Models/Doctor.swift:36","HealthApp/HealthApp/Models/Doctor.swift:51"],"effort":"M","area":"appstore-compliance"},
  {"id":"WS-13-03","title":"Appointment Prep sends health context to cloud AI with no consent","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/AppointmentPrepManager.swift:150","HealthApp/HealthApp/Views/ChatDetailView.swift:272"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-04","title":"Privacy Policy/Terms: inaccurate and missing claims (encryption, HF load, deletion, Apple Health)","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/PrivacyPolicyView.swift:23","HealthApp/HealthApp/Views/PrivacyPolicyView.swift:33","HealthApp/HealthApp/Views/PrivacyPolicyView.swift:75"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-05","title":"Reset Database leaves documents and plaintext thumbnails; dialog promises permanent deletion","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:776","HealthApp/HealthApp/Views/SettingsView.swift:48"],"effort":"M","area":"appstore-compliance"},
  {"id":"WS-13-06","title":"ITSAppUsesNonExemptEncryption absent","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1094"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-07","title":"Unused aps-environment entitlement","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/HealthApp.entitlements"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-08","title":"HealthKit usage string overstates/omits; permission sheet at launch","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1098","HealthApp/HealthApp/HealthAppApp.swift:285"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-09","title":"In-session medical disclaimer is a caption on the empty state only","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatEmptyStateView.swift:58"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-10","title":"ASC declarations: regulated medical device, age rating, category","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj:1095"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-11","title":"Model download unpinned main, no hash, interpreted jinja templates (2.5.2 question)","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:632","HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:878"],"effort":"M","area":"appstore-compliance"},
  {"id":"WS-13-12","title":"1024 icon has alpha channel; unused AppIcon-Doctor-Dark set","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Assets.xcassets/AppIcon-BisonHealthAI-Pro.appiconset/AppIcon-BisonHealthAI-Pro-1024.png"],"effort":"S","area":"appstore-compliance"},
  {"id":"WS-13-13","title":"No public privacy/support URL in repo; no reviewer demo path","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/SettingsView.swift:788"],"effort":"M","area":"appstore-compliance"},
  {"id":"WS-13-14","title":"iOS 26.0 deployment target is a business decision to record","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp.xcodeproj/project.pbxproj"],"effort":"S","area":"appstore-compliance"}
]
```
