# WS-11 — Performance, memory & battery

- **Agent / model**: Claude (Sonnet 5.5), read-only review
- **Date**: 2026-10-24
- **Commit reviewed**: f95cf804
- **Scope actually covered**: `HealthAppApp.swift`; `Database/DatabaseManager*.swift` (init, migration, fetch paths, encrypt/decrypt); `Managers/{HealthDataManager,DocumentManager,AIChatManager,AppLog}.swift`; `Services/{DocumentProcessor,NativeDocumentExtractor}.swift`; `Utils/{FileSystemManager,DocumentImporter,AIResponseCleaner,PlatformCapabilities}.swift`; `Views/{ChatDetailView,StorageUsageView,SplashScreenView}.swift` and the context-size slider in `OnDeviceLLMSettingsView.swift`; **the whole MLX path read statically**: `MLXOnDeviceClient.swift`, `MLXOnDeviceModels.swift`, `MLXModelDownloadManager.swift` (download/session/watchdog parts), plus `ChatSession.swift` in the resolved `mlx-swift-lm` checkout and two model `config.json` files fetched from the Hugging Face Hub.
- **Scope not covered**: Everything that needs hardware. No device was available. No Instruments / os_signpost traces. iPad was not run (iPhone 17 simulator only, as assigned). `StructuredText` (Textual) markdown cost was not measured. `fetchDocuments`/`fetchConversations` at scale were NOT measured: the app encrypts with a Keychain key I cannot reproduce outside the app, so I could not seed valid ciphertext. UI-driven scenarios (document import, 50-page OCR, 500-message chat) were not driven: on a fresh simulator install the HealthKit permission sheet covers the app at launch and I did not click through it.
- **Verdict**: No P0. The non-MLX app is fine at beta scale, with launch-time and list-load work that is wasteful but not alarming. The on-device AI path is **not** demonstrably safe: three P1 risks (unbounded KV-cache memory, generation left running into the background, untrimmed history on session rebuild) are all statically visible, none can be measured without a device, and the first is the most likely cause of an OOM kill on a tester's phone.
- **Counts**: P0=0 P1=3 P2=11 P3=1 (dropped: 0 — a few minor main-actor items were folded into WS-11-04/05/13 rather than dropped)

## Provenance legend (applies to every number in this file)

- **MEASURED-SIM**: measured on the iPhone 17 simulator (UDID 62468146…), Release build, signed ad hoc so the Keychain works. Simulator CPU is the host Mac's CPU and simulator memory is host-process memory. These are not device numbers.
- **MEASURED-MAC**: measured by compiling the app's own source file (or CryptoKit calls) into a standalone `swiftc -O` command-line binary on the host Mac. It is Mac CPU, not an iPhone. Scripts were in the session scratchpad only.
- **EST-CODE**: arithmetic from code constants and published model configs. Assumptions are stated each time.
- **MEASURED-DEVICE**: none. Not performed.

## Measurements table

| Scenario | Metric | Value | How measured | Provenance |
|---|---|---|---|---|
| Idle, fresh install (disclaimer/HealthKit sheet showing) | `phys_footprint` | 34 MB, peak 34 MB (this run had the DB unavailable because of unsigned entitlements, so treat as floor) | `footprint <pid>` | MEASURED-SIM |
| Idle, valid DB of 241 MB (1,500 doc rows, ~200 KB text each) | `phys_footprint` | 46 MB, peak 47 MB | `footprint <pid>` | MEASURED-SIM |
| Migration v12→v13 of that 241 MB DB (includes pre-migration backup copy and backup deletion) | wall time | all log lines (start, backup, "migrated") share one wall-second: **≤ 1 s**. The backup is deleted afterwards. Caveat: `copyItem` uses APFS clonefile, which is near-instant on both the Mac SSD and a device, but it is not the same flash | seeded v12 schema with `sqlite3`, launched, read `AppLog` file (1 s resolution) | MEASURED-SIM |
| Launch, empty DB | DB open + migration check + first health load | all within one log second (≤ 1 s) | `AppLog` file timestamps | MEASURED-SIM |
| Launch, splash | time before UI is usable | ≥ 5.0 s by construction (hard-coded delay, not skippable). Not observed: the HealthKit sheet covered the splash in my screenshots | code reading | EST-CODE |
| `AIResponseCleaner.clean` (the call made in the bubble's `body`) | per call, 1K / 4K / 12K / 30K characters | 0.62 / 2.08 / 6.09 / 14.98 ms | `swiftc -O` harness on the real file, 20 iterations | MEASURED-MAC |
| `cleanConversational(detectRunawayRepetition:false)` (the producer-side call, every 50 ms) | same sizes | 0.58 / 2.06 / 6.05 / 15.03 ms | same | MEASURED-MAC |
| `truncateRunawayRepetition` (WS-06-11 scan) | same sizes | 0.05 / 0.18 / 0.54 / 1.36 ms | same | MEASURED-MAC |
| AES-GCM seal / open | 50 KB / 500 KB | 0.007 / 0.068 ms seal; 0.013 / 0.070 ms open | CryptoKit harness | MEASURED-MAC |
| AES-GCM seal of a whole file | 10 MB / 50 MB | 2.0 / 8.8 ms | same | MEASURED-MAC |
| KV cache, MediPhi (Phi-3.5-mini architecture), fp16 | bytes per token | 393,216 (384 KiB): 32 layers × 32 KV heads × head_dim 96 × 2 (K and V) × 2 B | `config.json` fetched from `bisonnetworking/MediPhi-Instruct-mlx-4bit` | EST-CODE |
| same model, KV at the 16K default / 32K / 64K slider max | full-window KV size | 6.0 GiB / 12 GiB / 24 GiB (weights add about 2.15 GB) | arithmetic | EST-CODE |
| Qwen3.5-4B (hybrid, 8 of 32 layers are full attention, 4 KV heads, head_dim 256) | bytes per token | 32,768 (32 KiB), so about 2 GiB at 64K | `config.json` from `mlx-community/Qwen3.5-4B-MLX-4bit` | EST-CODE |
| One PDF page rendered for OCR at 300 DPI | bitmap size | letter page 2550×3300×4 B ≈ 33.7 MB, one page live at a time. Vision's own working set on top is unknown | arithmetic from `renderDPI = 300` | EST-CODE |
| Any MLX model load / inference / unload; GPU gate; `MLX.Memory.cacheLimit`; peak resident with model loaded; model + PDF coexisting | everything | **not measured, and cannot be measured in a simulator build**: both MLX files compile to nothing under `#if !targetEnvironment(simulator)`. Needs a physical iPhone, an Xcode Memory Graph or Instruments Allocations/Metal trace, and `os_proc_available_memory()` logging | n/a | NOT PERFORMED |
| Cold/warm launch on device, thermal behaviour, battery drain, cellular download behaviour, jetsam threshold | everything | not performed (no hardware) | n/a | NOT PERFORMED |

**Measured versus estimated**: the only measured values are the footprint, migration, `AIResponseCleaner` and AES rows. Everything about memory ceilings, KV cache, OCR working set and launch-to-interactive is estimated from code or not performed.

## Answers to the prompt's explicit questions

- **Does the 27B gate read installed memory?** Yes. `PlatformCapabilities.swift:19-34` uses `ProcessInfo.processInfo.physicalMemory` and `isiOSAppOnMac`, with the 24 GiB constant. It is enforced in `MLXModelInfo.isAvailable`. `allModels` filters on it (the UI list) and `performLoadModel` checks it again before loading. `model(withId:)` searches only `allModels`, so a persisted selection of the 27B on a smaller machine falls back to MediPhi rather than loading it. I found no UI path that bypasses it. Whether 24 GB is *enough* is WS-11-01's second half.
- **OS kills the app mid-load?** Load writes nothing persistent, so there is no corrupted state. `markCleanShutdown()` runs only when the scene backgrounds, so after a foreground jetsam the next launch shows the "Unexpected Shutdown Detected" alert. That works, but with no crash log, because jetsam leaves none.
- **Memory-warning handling?** None. There is no `didReceiveMemoryWarning` observer, no `DispatchSource.makeMemoryPressureSource`, no `os_proc_available_memory`, no `thermalState`, no `isLowPowerModeEnabled` anywhere in the app. The only memory reaction is unload-on-background (`MLXOnDeviceClient.swift:644`). See WS-11-10.
- **Model and large PDF resident together?** Chat and extraction clients are serialized through `MLXGPUGate` and `MLXModelResidency` so two models are never resident. A single model plus a document: the extractor holds the decrypted file, `PDFDocument`, and one 34 MB page bitmap, which is small next to the weights. The comment at `HealthAppApp.swift:116-120` shows the author already hit this jetsam. The text-OCR path does not unload the model, so peak ≈ model weights + KV + about 0.1–0.4 GB. That is an estimate with no basis for the Vision term.
- **Document processing is streaming?** Yes, page by page, in both the text OCR loop (`NativeDocumentExtractor.swift:~330`) and the vision loop (`runVisionPass`, capped at 6 pages on device). Not held all at once. The whole file is read and decrypted in one `Data` (bounded by the 50 MB import cap; see WS-11-12 for the scanner path that has no cap).
- **Database queries per screen?** Counted statically; see WS-11-04, -05, -06.
- **500-message chat**: load, scroll and per-token cost. The list is a `LazyVStack` with `.equatable()` bubbles and a 15 fps throttle (`AIChatManager.swift:646-700`), which is good. The per-token cost that matters is the cleaner (WS-11-07). Scroll smoothness and load time were not measured.

## Findings

### WS-11-01 — KV-cache memory is unbounded by device: 64K slider, fp16 KV, no memory limit; the default can exceed an iPhone on a full prompt
- **Severity**: P1 · **Confidence**: PLAUSIBLE · **Effort**: M
- **Location**: `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:737`; `MLXOnDeviceModels.swift:299-300`; `Views/OnDeviceLLMSettingsView.swift:332-340`
- **Scenario**: The default chat model is MediPhi (Phi-3.5-mini, **32 KV heads, no GQA**; config fetched from the Hub). Its fp16 KV cache costs 384 KiB per token (EST-CODE). The default window is 16K and `patientDataThreshold` deliberately lets patient data fill the window minus about 5.3K of reserves. A tester with a full record reaches roughly 11–14K prompt tokens on turn one, so KV ≈ 4.2–5.3 GiB on top of 2.15 GB of weights. That is above what an 8 GB iPhone allows even with the increased-memory-limit entitlement, so the likely outcome is jetsam mid-prefill. Moving the slider to 32K or 64K (offered with only "uses more memory" as caption) raises the full-window figure to 12 or 24 GiB. The 27B option has the same structure: weights 16.02 GB + KV. The gate admits any Mac with ≥ 24 GB installed, but a 24 GB machine has about 8 GB left for macOS plus the KV, which is tight even at the 16K default if Gemma-3-27B's KV is about 0.5 MB/token (I did not fetch that config; unverified). Qwen3.5-4B is fine (about 32 KiB per token).
- **Unverified link**: actual per-process memory ceiling on iPhone 17/17 Pro with the entitlement, and whether `RotatingKVCache` allocates in steps up to `maxKVSize` as assumed. Needs a device run with `os_proc_available_memory()` logged after prefill.
- **Evidence**:
  ```swift
  return GenerateParameters(
      maxTokens: maxTokensOverride ?? MLXModelInfo.configuredMaxTokens(for: model),
      maxKVSize: maxKVSizeOverride ?? MLXModelInfo.configuredContextSize,
      ...)   // kvBits not set; no MLX.Memory.memoryLimit anywhere; only cacheLimit (…Client.swift:580-583)
  public static let maxContextSize: Int = 65536
  ```
- **Fix**: Derive the allowed context ceiling from the model's KV bytes/token and `os_proc_available_memory()` / `physicalMemory`, and clamp the slider to it. Consider `kvBits: 4` or `8` for MHA models (the library supports it, `Evaluate.swift:68`). Set `MLX.Memory.memoryLimit`. Cap `patientDataAllowance` for the device. Fix sketch only; the right numbers need device data.
- **Blast radius**: `MLXContextBudget`, `AIChatManager.contextCompressionThreshold`, the settings slider, the extraction client (vision uses its own 4096 KV, so it is unaffected).
- **Verification**: On an 8 GB iPhone, load MediPhi, set 16K, send a message with about 12K tokens of patient data, and log `os_proc_available_memory()` before and after prefill. Repeat at 32K. Watch for jetsam in the Xcode console.

### WS-11-02 — A streaming reply is not cancelled when the app backgrounds; model unload waits behind it
- **Severity**: P1 · **Confidence**: PLAUSIBLE · **Effort**: M
- **Location**: `HealthAppApp.swift:323-343`; `MLXOnDeviceClient.swift:644-657` and `:283-284`
- **Scenario**: The user sends a question, the on-device model starts generating (held under `MLXGPUGate`), and the user switches apps. `handleScenePhaseChange(.background)` only starts `suspendOnDeviceLLMForBackground()`, which does `await MLXGPUGate.shared.acquire()` and so queues behind the running reply. Nothing cancels the generation and no `beginBackgroundTask` is requested. Metal command buffers submitted from a backgrounded app are rejected by iOS, and MLX turns that into a fatal error (known MLX-on-iOS failure mode, not reproduced here). Even if it does not crash, the multi-GB model stays resident in a backgrounded process, which the file's own comment calls "the first thing the OS reclaims".
- **Unverified link**: that MLX aborts (rather than throws) on background GPU submission in this library version. Needs a device: start a long reply, press Home, and check for a crash or `kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted`.
- **Evidence**:
  ```swift
  case .background:
      AppLog.shared.markCleanShutdown()
      MLXModelDownloadManager.shared.pauseForBackground()
      Task { await settingsManager.suspendOnDeviceLLMForBackground() }   // waits for the gate
  ```
- **Fix**: On `.inactive`/`.background`, cancel the in-flight generation task (the stream loop already tolerates cancel and keeps partial text), then unload. Add `isSuspendedForBackground` checks before each GPU submission.
- **Blast radius**: chat, extraction (vision page loop), `settingsManager.suspendOnDeviceLLMForBackground`.
- **Verification**: Device test above. Unit-test the gate with a cancelled holder.

### WS-11-03 — Session rebuild sends the entire untrimmed history; the library prefills it all and the rotating cache evicts the instructions
- **Severity**: P1 · **Confidence**: PLAUSIBLE (code path CONFIRMED; effect on device unmeasured) · **Effort**: M
- **Location**: `Managers/AIChatManager.swift:924-939`; `MLXOnDeviceClient.swift:313-322`, `:805-816`; library: `ChatSession.swift:392-396`
- **Scenario**: Every return from the background unloads the model and nils `chatSession` (`performUnloadModel`), so the next send rebuilds the session from `makeChatHistory(from: conversationHistory)`. The conversation history passed in is every non-empty message in the conversation, with no token budget. `ChatSession` appends all of it to the prompt and prefills it in 512-token steps (`ChatSession.swift:396`, `Evaluate.swift:122`). With a long chat (the review prompt's 500 messages is on the order of 100K tokens, EST-CODE) that is minutes of GPU/battery on the first reply after every app switch. Because `maxKVSize` is a rotating cache that keeps only the first 4 tokens, the persona, `PATIENT_DATA` and safety rules are the first thing evicted, which is exactly the failure the recent `MLXContextBudget` change set out to prevent. The comment at `MLXOnDeviceClient.swift` ("with history trimmed to fit") describes trimming that does not exist on this path.
- **Unverified link**: prefill throughput on A19/A19 Pro (I have no number), and whether the library trims history somewhere not exercised. I read `ChatSession.swift` and found no trimming.
- **Evidence**:
  ```swift
  mlxConversationHistory = messagesWithoutCurrent.filter { !$0.content.isEmpty }   // AIChatManager.swift:932
  ...
  chatSession = ChatSession(modelContainer, instructions: instructions, history: history, generateParameters: ...)
  ```
- **Fix**: Trim `mlxConversationHistory` to the newest turns that fit `window − instructions − reserves` before building `Chat.Message`s, using `MLXContextBudget.historyReserve` and a token estimate.
- **Blast radius**: only the on-device provider; cloud providers go through `ConversationContextBuilder`.
- **Verification**: Unit-test a pure trimming helper (the `MLXContextBudget` pattern). On a device, background and foreground a 100-message chat and time first-token latency.

### WS-11-04 — `loadHealthData` does a full-row decrypt per blood test (N+1)
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Managers/HealthDataManager.swift:149`, `:543-570`
- **Scenario**: At launch (`HealthDataManager.shared` auto-loads) and on every pull-to-refresh, each `BloodTestResult` that has `source_document_id` triggers `fetchDocument(id:)`. That builds a full `MedicalDocument`, decrypting `extracted_text`, `extracted_data` and `extracted_sections` for a single category check. 50 lab reports means 50 queries and 50 full-document decrypts plus JSON decodes, on the main actor. The crypto itself is cheap (MEASURED-MAC: 0.07 ms for 500 KB); the string/JSON materialization and SQLite reads are the real cost, which I did not measure.
- **Evidence**:
  ```swift
  for test in tests {
      if let documentIdString = test.metadata?["source_document_id"] ?? ..., let documentId = UUID(uuidString: documentIdString) {
          if let document = try? await databaseManager.fetchDocument(id: documentId) {
  ```
- **Fix**: One query selecting only `id, document_category` for the referenced ids, with no decryption.
- **Blast radius**: `HealthTabView` initial render; the same pattern may exist for other consumers of `fetchDocument`.
- **Verification**: Seed 100 lab docs, time `loadHealthData`, and count `fetchDocument` calls (should be 0 or 1 after the fix).

### WS-11-05 — `fetchConversations` decrypts every message of every conversation, twice per launch, on the main actor
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `Database/DatabaseManager+Chat.swift:49-72`, `:297-330`; callers `Managers/AIChatManager.swift:132-134` and `ContentView.swift:1459-1462`
- **Scenario**: `AIChatManager.init` starts `loadConversations()`, and the chat view's `.task` calls it again. Each call loads each conversation row and, inside the loop, runs a second query for that conversation's messages (N+1), decrypting all message bodies. The author flagged this (`ponytail:` comment); it is re-reported because the duplicate call doubles it and it scales with total history, not with the visible conversation. The 500-message figure in the prompt is the best case (one conversation); 50 conversations × 40 messages is 2,000 decrypt-and-decode operations, twice.
- **Evidence**:
  ```swift
  // ponytail: this eagerly decrypts every message of every conversation at startup ...
  while let row = try iterator.failableNext() {
      let conversation = try await buildChatConversation(from: row)   // → fetchMessages(for: id)
  ```
- **Fix**: Load conversation headers for the list and fetch messages lazily on selection; remove the duplicate `.task` load (or make `loadConversations` idempotent).
- **Blast radius**: `AIChatManager.conversations` consumers, `searchConversations`, `DocumentExporter`.
- **Verification**: Seed 50 × 40 messages, time launch to the chat list, and count `fetchMessages` calls.

### WS-11-06 — All SQLite work and migration run on the main actor, before the first frame
- **Severity**: P2 · **Confidence**: CONFIRMED (structure); magnitude not measured · **Effort**: L
- **Location**: `Database/DatabaseManager.swift:6` (`@MainActor`), `:138-257`; `HealthAppApp.swift` (`AppStartupHealth.init` touches `DatabaseManager.shared`)
- **Scenario**: The class is `@MainActor`, so every query and every `decryptData`/JSON decode in every `fetch*` runs on the UI thread. `DatabaseManager.shared` is constructed from `AppStartupHealth` inside the `App` struct, so the connection open, 9 `CREATE TABLE IF NOT EXISTS`, version check, migration and 12 `CREATE INDEX IF NOT EXISTS` all run before the first view. Measured: for an empty DB and for the 241 MB v12→v13 case this is ≤ 1 s on the Mac (MEASURED-SIM), which is fine. The risk is the list-load work above, which blocks the UI proportionally to library size on older hardware.
- **Evidence**:
  ```swift
  @MainActor
  class DatabaseManager: ObservableObject {
  ...
  while let row = try iterator.failableNext() { let document = try buildMedicalDocument(from: row) ... }
  ```
- **Fix**: Not a bug fix; either move reads behind a dedicated serial executor and return value types, or at minimum stop full-row decodes for list screens (select only the columns the list shows).
- **Blast radius**: very large (every manager). Listed here so it is not rediscovered. The cheapest wins are WS-11-04 and -05.
- **Verification**: Instruments Time Profiler on a 500-document library, filter main thread, launch and Documents tab.

### WS-11-07 — Response cleaning runs on every render and every 50 ms over the whole text (WS-06-11 answered)
- **Severity**: P2 · **Confidence**: CONFIRMED (measured on Mac; device scaling unmeasured) · **Effort**: S
- **Location**: `Views/ChatDetailView.swift:565`; `Utils/AIResponseCleaner.swift:116-136, 175-210`; `MLXOnDeviceClient.swift:371-385`
- **Scenario**: **The repetition scan is not the problem.** `truncateRunawayRepetition` measured 0.18 ms at 4K characters and 1.36 ms at 30K, and the 400-character amortization (`repetitionCheckCharacterInterval`) is adequate: at 30K it costs under 60 ms across a whole stream. The cost is `clean`/`cleanConversational`: 2.1 ms at 4K, 6.1 ms at 12K, 15 ms at 30K (MEASURED-MAC, -O). Per streaming second the main thread does the producer-side `cleanConversational` about 20 times (50 ms gate) and the bubble's `body` calls `clean` about 15 times (67 ms throttle), both on the full accumulated text: about 35 calls/s × 2.1 ms ≈ 73 ms/s at 4K characters (about 7% of the main thread), about 210 ms/s at 12K (about 21%), and over 500 ms/s at 30K. Cost per tick is linear in length, so a whole answer is quadratic. A 500 ms/s main-thread load is why a long reply would stutter, and it adds heat on top of inference. Contributors: about 50 full-string passes per call, `NSRegularExpression` recompiled per call, and `replacingOccurrences(of:"  +", options:.regularExpression)` recompiled once per line. iPhone vs Mac scaling is unknown; assume the same order of magnitude. `StructuredText` re-parsing the full markdown per tick adds an unmeasured amount.
- **Evidence**:
  ```swift
  let cleanedContent = AIResponseCleaner.clean(message.content)   // in buildMarkdownView(), runs in body
  return StructuredText(markdown: cleanedContent)
  ```
- **Fix**: The text is already cleaned by the producer (`cleanConversational`) and persisted cleaned, so drop the second `clean` from the view or memoize it per message id and content. Hoist the regexes into `static let`. Do the cleaning once per throttle tick, not per 50 ms and per render.
- **Blast radius**: all providers' streaming UI; `clean` is also used by `cleanTitle`.
- **Verification**: XCTest `measure {}` on a 12K-character string before and after (target < 1 ms), and Instruments on a long stream.

### WS-11-08 — Hard 5-second splash on every cold launch, not skippable
- **Severity**: P2 · **Confidence**: CONFIRMED (code); not observed on screen · **Effort**: S
- **Location**: `HealthAppApp.swift:44-52`; `Views/SplashScreenView.swift`
- **Scenario**: The splash overlay is removed by `DispatchQueue.main.asyncAfter(deadline: .now() + 5.0)` and has no tap gesture. The app is therefore never interactive in under 5 s regardless of how fast loading is. The measured loading itself fits in a second on an empty DB, so the splash is the dominant launch cost. On fresh installs the HealthKit permission sheet also appears over the splash before the disclaimer, which my screenshots at 2.5 s and 6.5 s both showed (a UX/privacy-ordering note for WS-13, not a perf finding).
- **Evidence**:
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { withAnimation(.easeInOut(duration: 0.8)) { showSplashScreen = false } }
  ```
- **Fix**: Dismiss when initial loads complete with a short minimum (about 1 s), or on tap.
- **Blast radius**: `HealthAppApp` only. UI tests that skip the splash use `--skip-disclaimer`.
- **Verification**: Screen-record a cold launch and time to first tappable control.

### WS-11-09 — Storage screen omits the models (up to 16 GB), the DB file and backups, so "Total Used" is wrong
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/StorageUsageView.swift:141-171`, `StorageInfo.totalSize` (`:236-240`)
- **Scenario**: The total is `healthDataSize + documentsSize + thumbnailsSize + chatHistorySize + cacheSize`, where health data and chat are the **encrypted payload estimates** (`SUM(LENGTH(...))`, `DatabaseManager.swift:723-731`), not the SQLite file. A user with the 2–3 GB models (or the 16 GB 27B) installed sees a total of a few MB and has no way to find the space or delete a model from this screen. Extracted text, which dominates the DB, is not counted either. The 241 MB test DB would be reported as a small fraction. Migration backups and the error-buffer files are also excluded.
- **Evidence**:
  ```swift
  var totalSize: Int64 { healthDataSize + documentsSize + thumbnailsSize + chatHistorySize + cacheSize }
  ```
- **Fix**: Add rows for on-device models (from `MLXModelDownloadManager`'s `directorySize`) and the actual DB file size, with a delete action per model.
- **Blast radius**: UI only.
- **Verification**: Compare the screen's total with `du` on the app container after downloading a model.

### WS-11-10 — No memory-pressure, thermal or Low Power Mode handling anywhere
- **Severity**: P2 · **Confidence**: CONFIRMED (absence by grep) · **Effort**: M
- **Location**: whole app; relevant loops: `Services/NativeDocumentExtractor.swift:~330` (OCR), `MLXOnDeviceClient.swift` (inference)
- **Scenario**: The extractor OCRs every page of up to 50 pages at 300 DPI (about 34 MB bitmap each, Vision `.accurate` plus `RecognizeDocumentsRequest` per page, about 1–2 s/page per the code comment), and the MLX path can run for minutes, with no check of `ProcessInfo.thermalState`, `isLowPowerModeEnabled`, or memory pressure. A tester processing a 50-page scan, or chatting on a warm device, will get thermal throttling with no backoff and no feedback. On memory pressure nothing is dropped except what unload-on-background already does. `grep` for `didReceiveMemoryWarning`, `makeMemoryPressureSource`, `thermalState`, `isLowPowerModeEnabled`, `os_proc_available_memory` returns nothing outside tests.
- **Fix**: Observe `thermalStateDidChange`; on `.serious` pause extraction between pages and cap generation length; on a memory warning, release the chat session/KV cache and the cached images.
- **Blast radius**: `DocumentProcessor`, MLX clients.
- **Verification**: Device soak test with a 50-page PDF while logging `thermalState`.

### WS-11-11 — Model downloads are foreground-only with no screen-awake handling; 2–16 GB downloads stall on auto-lock
- **Severity**: P2 · **Confidence**: PLAUSIBLE · **Effort**: M
- **Location**: `MLXOnDeviceLLM/MLXModelDownloadManager.swift:183-192`, `:490-502`; `UIApplication.isIdleTimerDisabled` is never set (grep)
- **Scenario**: Transfers use a `.default` `URLSession` (not a background session, so no OS-managed download), in 4 MB ranged slices. The code itself documents that iOS suspends the app about 30 s after backgrounding, and it pauses the stall watchdog for that case rather than keeping the download going. Screen auto-lock backgrounds the app, so a multi-GB download progresses only while the user keeps the screen on and the app in front. The partial file is kept and resumed (`discardIncompleteDownload` exists), so there is no data loss; this is a battery/UX cost. Metered paths are correctly opt-in (`allowsExpensiveNetworkAccess`). Good.
- **Unverified link**: real-world frequency of interruption; needs a device download over Wi-Fi with auto-lock at 30 s.
- **Fix**: Set `isIdleTimerDisabled = true` during an active foreground download (restore on completion or cancel), or move to a background `URLSession` configuration.
- **Blast radius**: download manager and settings UI only.
- **Verification**: Start the 3 GB download on a device, lock the screen and measure bytes after 2 minutes.

### WS-11-12 — The scanner import has no size cap and does whole-file crypto and PDF building on the main actor
- **Severity**: P2 · **Confidence**: PLAUSIBLE · **Effort**: S
- **Location**: `Utils/DocumentImporter.swift:187-230` (compare `validateFileSize` only in `importDocument`, `:362-372`); `Utils/FileSystemManager.swift:~120-150`
- **Scenario**: File imports are capped at 50 MB, and the `ponytail:` comment in `FileSystemManager.swift` relies on that cap to justify main-thread crypto. `importScannedDocument` builds a PDF from `VNDocumentCameraScan` pages by drawing full-resolution `UIImage`s into a PDF context, and then calls `storeDocument` with no size check. A 20-page scan drawn at camera resolution can plausibly exceed 50 MB (the PDF context re-encodes images; I did not measure the output size). Then `storeDocument` holds the plaintext `Data`, the sealed copy, and the written copy, so the transient is about 2–3× the file size, all on the main actor. Separately, `processDocument` and `runVisionPass` each call `retrieveDocument`, so a processed scan is read and decrypted twice (`DocumentProcessor.swift:726`, `:1114`).
- **Unverified link**: the scanned PDF size; measure by scanning 20 pages on a device.
- **Fix**: Apply `validateFileSize` (or downscale and JPEG-compress pages) in the scanner path, and pass the already-decrypted `Data` into the vision pass.
- **Blast radius**: scanner import, vision pass.
- **Verification**: Scan 30 pages on a device and log `pdfData.count` and peak memory.

### WS-11-13 — Error-level logging blocks the calling thread (often main) on a sync queue, an fsync and a full rewrite of the error buffer
- **Severity**: P2 · **Confidence**: PLAUSIBLE (magnitude unmeasured) · **Effort**: S
- **Location**: `Managers/AppLog.swift:448-458`, `:497-510`
- **Scenario**: For `.error`/`.critical` the caller does `logQueue.sync`, which appends to the log with `synchronizeFile()` (fsync), then `persistToErrorBuffer` reads the whole buffer, splits it into lines, builds a new `ISO8601DateFormatter` and parses the timestamp of every line, and rewrites it atomically (a second fsync plus rename). Several loops log `.error` per item from the main actor: `DatabaseManager+HealthData.swift` logs one error per undecryptable record, and `NativeDocumentExtractor` per failing page. With a rotated key or a corrupted table, N records mean N synchronous double-fsync stalls on the UI thread. Info-level logging is correctly async; it opens, seeks and closes the file per line, which is wasteful but off-main.
- **Unverified link**: per-call latency on device flash. I did not measure it.
- **Fix**: Make durable logging async with a coalesced flush (or `sync` only for `.critical`), and cache the formatter.
- **Blast radius**: all `AppLog` callers.
- **Verification**: Time 100 consecutive `AppLog.shared.error` calls on a device from the main thread.

### WS-11-14 — Models live in `Caches/` (purgeable) and are invisible to storage UI; migration aborts if the pre-migration backup copy fails
- **Severity**: P2 · **Confidence**: PLAUSIBLE · **Effort**: S–M
- **Location**: `MLXModelDownloadManager.swift:1115-1127`; `Database/DatabaseManager.swift:~455-465` (`createBackupBeforeMigration`, called with `try`)
- **Scenario**: (a) Weights are written under `cachesDirectory/models/...`. iOS may delete Caches contents under storage pressure, which is exactly when a user with 16 GB of models is most likely to be low on space. The app handles missing files by re-validating (`localModelDirectory` returns nil → `modelNotDownloaded`), so this fails soft but costs a multi-GB re-download. (b) `performDatabaseMigration` calls `try createBackupBeforeMigration()`. If the copy fails (disk full, since a clone is not free once the DB diverges), the throw makes `DatabaseManager.shared` record an `initializationError`, so a user with a low-space device and a large library cannot upgrade at all. On APFS `copyItem` clones, so (b) is unlikely at v12→v13 (measured ≤ 1 s for 241 MB), but any migration from before v11 reads the whole documents table into memory (`encryptDocumentPHIColumns` accumulates every row in `pending`) on the main thread inside `init`. That path is the only one that could approach the iOS launch watchdog; I did not measure it (WS-06-12 for pre-v11 libraries remains unmeasured).
- **Unverified link**: actual cache-purge policy for large files in an active app, and a real pre-v11 library.
- **Fix**: (a) Store weights in Application Support with `isExcludedFromBackup`. (b) Treat a failed backup as a warning when free space is low, or surface a specific "free up space" error; stream the v11 pass in batches.
- **Blast radius**: download manager path code, `localModelDirectory`, the migration path.
- **Verification**: Fill a simulator disk and run the migration; list `Caches` after `simctl` low-storage simulation.

### WS-11-15 — Whole-file crypto on the main actor (existing `ponytail:` deferral): measured, not worse than documented
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `Utils/FileSystemManager.swift:7-10`, `:130-160`
- **Scenario**: The deferral says whole-file encrypt/decrypt on the main actor is "bounded by the 50 MB import cap". Measured AES-GCM seal of 50 MB: 8.8 ms (MEASURED-MAC), 2 ms for 10 MB. **Crypto is not the cost**; per-row `decryptData` at 0.07 ms per 500 KB is likewise negligible, so "decrypt-per-row is expensive" is refuted for this app. What the deferral understates is the memory (about 2–3× file size) and the file I/O on the main thread (see WS-11-12 for the one place the cap does not apply).
- **Fix**: none needed beyond WS-11-12.
- **Blast radius**: n/a.
- **Verification**: n/a.

## Structural risks (max 5 bullets)

- The on-device AI path has no runtime memory model at all: no available-memory check before load, no `memoryLimit`, no per-model KV accounting, no memory-warning response. Everything depends on constants chosen by hand on one machine.
- `DatabaseManager` and `FileSystemManager` being `@MainActor` makes every future list screen a main-thread decrypt-and-decode job; the cheap fixes (WS-11-04/05) buy headroom but do not change the shape.
- Chat history is stored and re-loaded whole; no layer owns "how much history is enough" for the on-device provider (cloud has `ConversationContextBuilder`; MLX does not).
- Performance claims in comments (`"trimmed to fit"`, `"bounded by the 50 MB cap"`) have already drifted from the code in two places; consider a test per claim.
- Nothing in the app negotiates background execution (no `beginBackgroundTask`, no background `URLSession`, no BGTask), so every long operation (extraction, download, generation) silently depends on the user keeping the screen on.

## Machine-readable summary

```json
[
  {"id":"WS-11-01","title":"KV-cache memory unbounded by device (64K slider, fp16 KV, no memory limit)","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:737","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceModels.swift:300","HealthApp/HealthApp/Views/OnDeviceLLMSettingsView.swift:332"],"effort":"M","area":"performance"},
  {"id":"WS-11-02","title":"Streaming reply not cancelled on background; unload waits behind GPU gate","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/HealthAppApp.swift:323","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:644"],"effort":"M","area":"performance"},
  {"id":"WS-11-03","title":"Session rebuild sends entire untrimmed history; instructions evicted by rotating cache","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Managers/AIChatManager.swift:932","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:313"],"effort":"M","area":"performance"},
  {"id":"WS-11-04","title":"loadHealthData N+1 full-document decrypt per blood test","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/HealthDataManager.swift:553"],"effort":"S","area":"performance"},
  {"id":"WS-11-05","title":"fetchConversations decrypts all messages of all conversations, twice per launch","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:49","HealthApp/HealthApp/Managers/AIChatManager.swift:132","HealthApp/HealthApp/ContentView.swift:1459"],"effort":"M","area":"performance"},
  {"id":"WS-11-06","title":"All SQLite work and launch migration on the main actor","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:6"],"effort":"L","area":"performance"},
  {"id":"WS-11-07","title":"AIResponseCleaner.clean on every render and every 50ms over full text (measured 2ms@4K, 15ms@30K on Mac)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/ChatDetailView.swift:565","HealthApp/HealthApp/Utils/AIResponseCleaner.swift:116"],"effort":"S","area":"performance"},
  {"id":"WS-11-08","title":"Hard 5-second non-skippable splash on every cold launch","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/HealthAppApp.swift:47"],"effort":"S","area":"performance"},
  {"id":"WS-11-09","title":"Storage screen omits models, DB file and backups; total understated","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/StorageUsageView.swift:141"],"effort":"S","area":"performance"},
  {"id":"WS-11-10","title":"No memory-pressure, thermal or Low Power Mode handling anywhere","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:330"],"effort":"M","area":"performance"},
  {"id":"WS-11-11","title":"Model downloads foreground-only with no idle-timer handling","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:183"],"effort":"M","area":"performance"},
  {"id":"WS-11-12","title":"Scanner import has no size cap; main-actor whole-file work; document decrypted twice","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Utils/DocumentImporter.swift:187","HealthApp/HealthApp/Services/DocumentProcessor.swift:726"],"effort":"S","area":"performance"},
  {"id":"WS-11-13","title":"Error-level logging blocks caller on sync queue, fsync and full error-buffer rewrite","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Managers/AppLog.swift:455","HealthApp/HealthApp/Managers/AppLog.swift:497"],"effort":"S","area":"performance"},
  {"id":"WS-11-14","title":"Models stored in purgeable Caches; migration aborts if backup copy fails; v11 pass loads whole library","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:1124","HealthApp/HealthApp/Database/DatabaseManager.swift:455"],"effort":"M","area":"performance"},
  {"id":"WS-11-15","title":"Main-actor whole-file crypto deferral: measured negligible CPU, not worse than documented","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/FileSystemManager.swift:7"],"effort":"M","area":"performance"}
]
```
