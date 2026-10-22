# WS-12 — On-device model lifecycle (MLX)

- **Agent / model**: Claude Sonnet 5.5 (Claude Code subagent)
- **Date**: 2026-10-22
- **Commit reviewed**: af05db1
- **Scope actually covered**: all four files in `HealthApp/HealthApp/MLXOnDeviceLLM/` (read in full); `Views/OnDeviceLLMSettingsView.swift` (full); `Views/StorageUsageView.swift` (full); `Utils/PlatformCapabilities.swift`; `Managers/SettingsManager.swift` (client factory, preload, lifecycle); `HealthAppApp.swift` scene-phase handler; `Managers/AIChatManager.swift` (send path, context build/compress, title generation); `Utils/ConversationContextBuilder.swift` (limits). Library sources at the pinned revisions in DerivedData, read-only: `mlx-swift-lm` 2.31.3 (`Load.swift`, `ModelFactory.swift`, `LLMModelFactory.swift`, `Tokenizer.swift`, `KVCache.swift`, `ChatSession.swift`, `LanguageModel.swift`) and `swift-transformers` 1.2.1 (`HubApi.swift`). Hugging Face repo file listings for the three catalog repos (via the HF connector). Current App Review Guidelines (fetched, see App Store section).
- **Scope not covered**: no inference, download or load was executed. MLX paths are compiled out of the simulator (WS-03) and I was told not to use the simulator or xcodebuild, so every behavioural claim is a source trace. No physical device. The last ~14 KB of the Guidelines page was not read (it covers sections past 5.x that do not bear on this brief). `DocumentProcessor`'s use of the VLM was only read for the load path.
- **Verdict**: Not beta-ready for the on-device story as marketed ("No internet required after downloading"). The downloader itself is careful (ranged resume, size-checked atomic rename, shard-set check), but the model *load* path delegates to a library that re-contacts Hugging Face and needs Hub metadata the custom downloader never writes, and a 16 GB download can be wiped by three ordinary hiccups.
- **Counts**: P0=0 P1=3 P2=8 P3=3 (dropped: 0)

## Direct answers to the lead's questions

1. **Can a truncated or corrupt model be marked usable?** *Truncated weight shard through the app's own download path: no.* A file is renamed from `.incomplete` to its final name only when the byte count equals the Hub-advertised size (`MLXModelDownloadManager.swift:683-692`), and the shard set is checked against the `weight_map` of the index (`:1097-1111`). *Corrupt or wrong-content weights: yes, the app has no hash.* Also *marked usable with missing non-weight files*: `isModelCacheValid` checks only `config.json` plus shard names, so a kill in the window where `config.json` has landed but `tokenizer.json` has not yields a model flagged "Downloaded" that cannot tokenize (WS-12-04). A SHA-256 check does exist, but only as an accidental side effect of `loadContainer` on the first online load (WS-12-01).
2. **App killed mid-download:** the `.incomplete` partials stay on disk; nothing is marked downloaded; there is no auto-resume and no UI for the partials. Tapping Download again resumes from the partial's byte offset (that part works). The partials are never counted or reclaimed by any UI, so up to ~16 GB is stranded (WS-12-05). The download is not a background `URLSession`; there is no background mode, no `beginBackgroundTask`.
3. **Is the memory gate sound?** The *gate itself* is: `ProcessInfo.physicalMemory` (installed, not available) `>= 24 GiB` AND `isiOSAppOnMac`, with a unit test, applied to the catalog (`isAvailable`), the start of a download, the load, and the UI list. What is not sound is everything around it: smaller models on iPhone/iPad have no device-memory gate at all, a context slider goes to 64K, and there is no memory-warning handler or crash-loop breaker if a gated load still gets the process killed (WS-12-08).
4. **Does `compactChatRules` survive truncation?** It is appended at the *end* of the system block, but the system block is at the *start* of the context, and the on-device KV window is a sliding window that keeps only the first 4 tokens and evicts the oldest. So the rules survive longer than the persona and patient data that precede them in the same block, but they go before every conversation turn once the window overflows. The context budget (90% of the window for patient data alone) makes overflow likely for users with real records (WS-12-02). The on-device path therefore has its own flaw on top of the shared compressor flaw (tracker item 19).
5. **WS-03-03 code trace:** nothing cancels; `suspendForBackground` only queues behind the GPU gate. No background modes, `BGTask` or `beginBackgroundTask` anywhere. Details and a device test plan below. Left PLAUSIBLE.
6. **Counts by severity:** P0=0, P1=3, P2=8, P3=3.

## Model inventory

| Model | Repo (revision) | Size on Hub | Files / shards | Memory gate | Eligible devices | Verified how |
|---|---|---|---|---|---|---|
| MediPhi Instruct (LLM) | `bisonnetworking/MediPhi-Instruct-mlx-4bit` (`main`, unpinned) | 2.15 GB (`estimatedSizeBytes` 2,150,000,000; Hub lists 2,149,696,492 weights) | 1 safetensors + index + tokenizer/config JSON + `chat_template.jinja` | **None** | Every device the app installs on (iOS 26 target) | Size equality per file; names-only set check; no hash in app |
| MedGemma 27B Chat (LLM) | `mlx-community/medgemma-27b-text-it-4bit` (`main`, unpinned, third-party org) | 16.02 GB (Hub shards: 5,366,222,432 + 5,349,891,492 + 5,271,313,298) | 3 safetensors shards + index + `tokenizer.json` (33 MB) + `tokenizer.model` (4.7 MB, non-JSON, fetched via the allow-list) + JSON/Jinja | `isiOSAppOnMac && physicalMemory >= 24 GiB` (`PlatformCapabilities.swift:17-35`) | Apple-silicon Macs running the iOS app with >= 24 GB | Size equality per shard; index `weight_map` names; no hash in app |
| Qwen 3.5 4B Vision (VLM) | `mlx-community/Qwen3.5-4B-MLX-4bit` (`main`, unpinned, third-party org) | 3.03 GB | 1 safetensors + index + `tokenizer.json` (20 MB LFS) + `vocab.json` + preprocessor JSONs | **None** | Every device | Same |

"Verified how" is the same for all three; the only hash check anywhere is inside the library on load (WS-12-01).

## Download state machine

```
                         startDownload(model)
                guards: isAvailable, !isDownloading, !isModelDownloaded     (:142-155)
                                   |
                                   v
 [Idle] ----------------> [Connecting]  listFiles(main) -> filter *.safetensors/*.json/*.jinja
   ^                           |         + 7 tokenizer names; sort largest first            (:469-480)
   |                           v
   |                     [Downloading]  <=3 files in parallel; each file = 4 MiB Range GETs
   |                           |        appended to <file>.incomplete; resume = size of partial
   |                           |        file done iff bytes == advertised size -> atomic rename (:683-692)
   |                           |
   |        stall >60 s  or   any thrown error (disk full, HTTP, timeout, app resumed from suspend)
   |                           |
   |                           v
   |                     [Retrying]  automaticStallRetryCount++ (max 2, NEVER reset mid-download)
   |                           |        partials kept; re-enters Connecting                    (:836-887, :893-936)
   |                           |
   |   count exhausted / user Cancel
   |        |                  |
   |        v                  v all files renamed
   |   [Failed/Cancelled]  [Validating] isModelCacheValid: config.json + shard names only      (:206, :1046-1115)
   |   cleanupIncompleteDownload                |
   |   WIPES whole model dir (:1125-1144)       v
   +<-------------------------------------- [Downloaded]  id inserted in UserDefaults set; progress=1.0 (:216-224)

 App killed in Connecting/Downloading/Retrying:  -> partials stay, state lost, [Idle] on relaunch, not reclaimed.
 App backgrounded: plain URLSession (no background config), suspended by iOS; watchdog sees "no bytes" on return
                   and spends a retry. Hits Failed after 3 occurrences.
 Launch: refreshModelStatus() re-runs the same names-only validity check for every catalog model (:355-368).
```

## Findings

### WS-12-01 — The load path re-contacts Hugging Face every time, needs Hub metadata the custom downloader never writes, and can silently re-download shards under the GPU gate
- **Severity**: P1 · **Confidence**: PLAUSIBLE (every link below is read in source at the pinned revisions; not executed, since MLX is compiled out of the simulator and no device was available. Unverified link: runtime behaviour of the Hub offline detection on a real device) · **Effort**: M
- **Location**: `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:545-551` (call), `MLXModelDownloadManager.swift:491-517` (writes files with no metadata); library `mlx-swift-lm/Libraries/MLXLMCommon/Load.swift:21-45`, `swift-transformers/Sources/Hub/HubApi.swift:902-939` and `:778-820`
- **Scenario**: The app downloads files itself straight into `Caches/models/<repo>` and never writes the `.cache/huggingface/download/*.metadata` files that `swift-transformers` uses. But `LLMModelFactory.loadContainer(configuration:)` (and the VLM equivalent) always calls `downloadModel(hub:configuration:)`, which calls `hub.snapshot(from: repo, revision: "main", matching: ["*.safetensors","*.json","*.jinja"])`. In `snapshot`: (a) if the network path is satisfied, it lists the repo and HEADs every matching file on huggingface.co, **on every model load** (each foreground return reloads the model because `suspendForBackground` unloads it); for each LFS file with no local metadata it computes SHA-256 of the whole local file, and if the hash differs, or the repo's `main` has moved, it **re-downloads the file inside `loadContainer`** with no UI, no progress and `MLXGPUGate` held. (b) If the path is unsatisfied (airplane mode), it takes the offline branch and throws `offlineModeError("Metadata not available for …")` for any file lacking metadata. So: download MediPhi at home, switch to airplane mode, kill the app, ask a question: load throws (first load must be online). After one online load the metadata exists for globbed files, but MedGemma's `tokenizer.model` is not matched by the globs, never gets metadata, and is present in the directory, so MedGemma can never load offline. In offline mode the library also recomputes SHA-256 of every LFS file on every load (about 16 GB read for MedGemma).
- **Evidence**:
  ```swift
  // MLXOnDeviceClient.swift:545-547
  modelContainer = try await LLMModelFactory.shared.loadContainer(
      configuration: configuration
  )
  // mlx-swift-lm Load.swift:30-36
  let modelFiles = ["*.safetensors", "*.json", "*.jinja"]
  return try await hub.snapshot(from: repo, revision: revision, matching: modelFiles, progressHandler: progressHandler)
  // swift-transformers HubApi.swift:924-926 (offline branch)
  guard let localMetadata else {
      throw EnvironmentError.offlineModeError(("Metadata not available for \(fileUrl.lastPathComponent)"))
  ```
  Repo fact: `hf://models/mlx-community/medgemma-27b-text-it-4bit` contains `tokenizer.model` (LFS, 4.7 MB), outside the glob; `grep -rn "\.metadata\|huggingface/download" MLXOnDeviceLLM` finds nothing.
- **Fix**: stop using the Hub-aware `loadContainer(configuration:)` for local models: build `ModelConfiguration(directory: modelDirectory, ...)` so `downloadModel` returns the directory without network and the tokenizer loads locally. Then own integrity in the downloader (WS-12-04).
- **Blast radius**: every on-device chat, title and VLM-extraction load; airplane-mode demo and App Review check; privacy copy ("No internet required", WS-07 egress row lists only the one-time download); `MLXGPUGate` hold time (WS-12-09).
- **Verification**: physical device, release build. (1) Download MediPhi, enable airplane mode *before* the first chat, expect failure today and success after the fix. (2) With a proxy or Little Snitch, observe HEAD/GET to huggingface.co on each load. (3) Corrupt one byte in `model.safetensors` and observe a silent multi-GB re-download today.

### WS-12-02 — On-device context budget guarantees window overflow; the sliding KV window evicts the persona and patient data first, and `compactChatRules` goes with them
- **Severity**: P1 · **Confidence**: PLAUSIBLE (mechanism CONFIRMED in library source; unverified link: how much the specific models' answers degrade when the system block's KV entries are evicted, needs a device run) · **Effort**: M
- **Location**: `MLXOnDeviceLLM/MLXOnDeviceClient.swift:629-656` and `:659-670`; `Utils/ConversationContextBuilder.swift:15-19`; `Managers/AIChatManager.swift:43` and `:1133-1141`; library `mlx-swift-lm/Libraries/MLXLMCommon/LanguageModel.swift:224-226`
- **Scenario**: For the on-device provider `contextSizeLimit` is `configuredContextSize` (default 16,384), which is also passed as `maxKVSize`. The health context is compressed only above 90% of that same number, so patient data alone may occupy ~14.7K tokens. The instructions are `persona` + `PATIENT_DATA…` + `Rules…`, set once as the system message, then every turn is appended behind them. mlx-swift-lm builds `RotatingKVCache(maxSize: maxKVSize, keep: 4)`: it keeps the first 4 tokens and discards the oldest beyond the window. With ~1.6K tokens of headroom, the persona, prior turns, the user message and a reply of up to 1,200 tokens (MediPhi default; slider allows 4,096) overflow within the first one or two exchanges, and eviction starts at the head: persona first, then the beginning of `PATIENT_DATA`; the rules block (last in the system block) survives marginally longer but is always evicted before any conversation turn. The "rules last so they stay salient" comment addresses recency, not eviction. Users with little data (a few KB) are unaffected, which hides this in dev. Related: WS-04-03 (cloud-side compressor and a PLAUSIBLE mention of rotation). This finding supplies the library evidence and the rules-specific consequence; the guard against "start, stop or change a medicine or dose" is among what silently disappears. Truncation is unannounced: no UI shows that a window overflow happened.
- **Evidence**:
  ```swift
  // MLXOnDeviceClient.swift:640-646
  // Keep the operational rules last so they remain salient after a large patient payload.
  if !sections.isEmpty {
      let maxTokens = MLXModelInfo.configuredMaxTokens(for: modelProvider())
      sections.append(Self.compactChatRules(maxTokens: maxTokens))
  }
  // ConversationContextBuilder.swift:17-18 : onDeviceLLM limit == configuredContextSize
  // AIChatManager.swift:43 : threshold = Int(Double(contextSizeLimit) * 0.9)
  // LanguageModel.swift:224-226 (mlx-swift-lm 2.31.3)
  if let maxKVSize = parameters?.maxKVSize {
      RotatingKVCache(maxSize: maxKVSize, keep: 4)
  ```
- **Fix**: budget the window: reserve for instructions + rules + history + `maxTokens` before sizing patient data (priority order: rules, allergies/meds/conditions, then bulk); re-assert the rules at the *end* of the prompt each turn (or in the user turn), and rebuild the session when `promptTokenCount + maxTokens` approaches `maxKVSize` so the system block is re-prefilled rather than evicted. Surface "context trimmed" in the UI. Pair with the fix for tracker item 19.
- **Blast radius**: all on-device chat; `AIChatManager`, `ConversationContextBuilder`, `MLXOnDeviceClient`, Settings context-size slider.
- **Verification**: unit test the budget arithmetic (fixed costs + maxTokens + data <= window). On device: load a record with ~12K tokens of documents, put an allergy at the head of `PATIENT_DATA`, ask three questions, check the answer and `promptTokenCount` in `AIResponse` metadata against `maxKVSize`.

### WS-12-03 — A 16 GB download is wiped after three ordinary interruptions; backgrounding spends the retries
- **Severity**: P1 · **Confidence**: PLAUSIBLE (code path fully traced; unverified link: whether a suspended default `URLSession` slice errors or merely stalls on resume, either way a retry is consumed) · **Effort**: M
- **Location**: `MLXModelDownloadManager.swift:94-98`, `:112-121`, `:794-802`, `:836-855`, `:893-899`, `:1125-1144`
- **Scenario**: `automaticStallRetryCount` is shared by stall retries and transfer-error retries and is reset only on a fresh `startDownload`, success, or cancel, never when progress resumes. The download uses `URLSessionConfiguration.default` (not `.background`), and the app declares no background modes or background task, so iOS suspends the transfer ~30 s after the user switches away. On return the 1-second monitor sees `now - lastMovement > 60` immediately and calls `retryDownloadAfterStall` (retry 1); a transfer error from the dead socket can consume another. The third occurrence hits "Giving up", which calls `cleanupIncompleteDownload`, deleting the entire model directory including every finished shard. For the 16 GB MedGemma (or 3 GB Qwen on a phone) a user who checks mail three times, or loses Wi-Fi three times over an hour, loses everything and sees "Download stalled. Check your network connection and tap Download to retry" with all progress gone. The comment at `:1117` justifies the wipe by the storage UI being unable to reclaim bytes, which is a storage-UI gap (WS-12-05), not a reason to destroy completed shards.
- **Evidence**:
  ```swift
  // :836-855
  guard automaticStallRetryCount < Self.maxAutomaticStallRetries else {
      AppLog.shared.mlx("[MLXDownload] Giving up after ...")
      ...
      cleanupIncompleteDownload(for: model)
      removeDownloadedModel(model)
      downloadError = "Download stalled. Check your network connection and tap Download to retry."
  ```
- **Fix**: reset the retry counter whenever bytes advance; on terminal failure keep completed shards and partials (surface them in the storage UI with a "Resume"/"Remove" choice); move the transfer to `URLSessionConfiguration.background` (or at minimum treat scene-phase suspension as a pause, not a stall).
- **Blast radius**: download manager, `OnDeviceLLMSettingsView`, privacy of bandwidth/cost for users.
- **Verification**: device or macOS-hosted iOS app: start MedGemma/Qwen, background the app for 45 s three times; today the dir is deleted and `downloadedBytes` returns to 0. Unit-test the counter with a fake clock.

### WS-12-04 — No cryptographic or revision integrity; "usable" means "config plus shard names present"
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `MLXModelDownloadManager.swift:475-477`, `:502-505`, `:574-577`, `:604-609`, `:663-671`, `:1046-1115`, `:206`
- **Scenario**: (1) Size equality is checked against a size that comes from the same server, with `revision: "main"` for MedGemma/Qwen, repos owned by `mlx-community`, so a repo update between the listing and a resumed attempt (or between attempts) splices bytes from two revisions: the resume appends to a partial from the old revision, the total size matches, the rename happens, and no hash is compared. A re-upload that keeps shard sizes (same quantisation) also passes the "already complete" skip at `:574` with stale weights. (2) After an unsynced write (battery death, crash), APFS can retain the extended size with zeroed tail blocks; `synchronize()` runs only at the end of each file (`:681`), so the next resume trusts the partial's length. (3) The validity check only needs `config.json` plus shard names. Files are fetched largest-first, so `config.json` lands near the end; a kill after `config.json` but before `tokenizer.json` finishes, then relaunch, runs `refreshModelStatus`, which marks the model Downloaded with no tokenizer. (4) Entries with a missing Hub `size` are unverified (`expectedBytes == 0` path). Net: a truncated shard cannot be marked usable through normal paths, but a corrupt one can, and a model missing required auxiliary files can.
- **Evidence**:
  ```swift
  // :1093-1094
  guard hasConfig else { return false }
  guard !indexFiles.isEmpty else { return hasSafetensors }   // names/extensions only
  // :683
  if expectedBytes > 0, completedBytes != expectedBytes { throw ... }  // size only, from the same server
  ```
- **Fix**: pin a commit SHA per catalog entry; take the LFS `oid` (sha256) from the tree listing and verify each LFS file after rename (stream hash, off the main actor); require every listed file, not just config and shards; `fsync` partials periodically. Records of expected hashes can live in `MLXModelInfo`.
- **Blast radius**: download manager, catalog; WS-12-01's fix removes the library's accidental hash check, so this becomes the only line of defence.
- **Verification**: unit test `isModelCacheValid` with a directory missing `tokenizer.json`; flip a byte in a shard fixture and assert the verifier rejects it.

### WS-12-05 — Killing the app mid-download strands up to 16 GB that nothing counts, shows or reclaims
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `MLXModelDownloadManager.swift:355-368`, `:374-382`, `:1117-1144`; `Views/OnDeviceLLMSettingsView.swift:351-375`
- **Scenario**: The comment says terminal paths delete partials precisely because otherwise "no UI can reclaim them". A process kill (swipe-away, jetsam, crash, reboot) is a terminal path that never reaches that code. On relaunch the model is not in `downloadedModelIds`, so `totalStorageUsed` (which iterates only downloaded models) ignores the directory, the model row offers a fresh Download, and nothing prompts "resume or discard". If the user never returns, the partials sit in `Caches/models/...` until iOS purges Caches under pressure.
- **Evidence**:
  ```swift
  // :374-380
  for model in MLXModelInfo.allModels where downloadedModelIds.contains(model.id) {
      total += Self.directorySize(at: huggingFaceCacheDirectory(for: model))
  ```
- **Fix**: at launch and in `refreshModelStatus`, detect `*.incomplete` or non-valid directories; show "Partial download, X GB: Resume / Delete" and include them in storage totals.
- **Blast radius**: settings view, storage reporting.
- **Verification**: start a download, force-quit at ~30%, relaunch, check Settings storage and the file system; then tap Download and confirm resume from offset.

### WS-12-06 — No free-space check before a multi-gigabyte download; a full disk also starves the health database
- **Severity**: P2 · **Confidence**: PLAUSIBLE (no check exists, confirmed by grep for `volumeAvailableCapacity*`, `systemFreeSize`, `availableCapacity`; the knock-on SQLite failure is inferred) · **Effort**: S
- **Location**: `MLXModelDownloadManager.swift:142-161` (no preflight); `:604-609` (writes)
- **Scenario**: A user with 6 GB free taps Download on Qwen (3.03 GB) or a Mac user on MedGemma (16.02 GB, partials are grown in place). The download fills the volume. While it runs, other writes fail: SQLite inserts for vitals, chat messages and imported documents hit disk-full, and the user sees generic failures in unrelated screens. At the end the file write throws, the two automatic retries re-fail, and WS-12-03's terminal path deletes the partial; the user lost the download and may have lost other writes in between.
- **Evidence**:
  ```swift
  // startDownload: guards isAvailable / isDownloading / isModelDownloaded only
  guard model.isAvailable else { ... }
  guard !isDownloading else { ... }
  guard !isModelDownloaded(model) else { ... }
  ```
- **Fix**: before starting, read `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` and require `estimatedSizeBytes` plus a reserve (e.g. 2 GB, plus 10% headroom); disable the button with a clear message; stop and keep partials on `ENOSPC` instead of retrying.
- **Blast radius**: settings view; database error surfaces if triggered.
- **Verification**: fill a test device to leave 1 GB, attempt Qwen, expect a preflight refusal.

### WS-12-07 — A multi-gigabyte download starts on cellular on one tap, overriding Low Data Mode
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `MLXModelDownloadManager.swift:118-119`; `Views/OnDeviceLLMSettingsView.swift:124-126`, `:515-523`
- **Scenario**: A tester on cellular taps the "3.03 GB" button for Qwen; the session is explicitly configured to allow expensive (cellular, hotspot) and constrained (Low Data Mode) paths, nothing checks `NWPath.isExpensive`, and there is no confirmation. Roaming or capped users pay for 2–3 GB (iPhone) with no warning beyond the button label. The Guidelines' 4.2.3(ii) asks apps that need a download to "disclose the size of the download and prompt users before doing so"; the size is on the button, but there is no prompt.
- **Evidence**:
  ```swift
  configuration.allowsExpensiveNetworkAccess = true
  configuration.allowsConstrainedNetworkAccess = true
  ```
- **Fix**: confirm dialog on every download stating size and network type; default `allowsExpensiveNetworkAccess = false` and require an explicit "Download over cellular" choice; honour Low Data Mode.
- **Blast radius**: download manager and settings view.
- **Verification**: device on cellular only, tap Download; expect a confirmation or refusal.

### WS-12-08 — Memory gate is sound for MedGemma, but nothing protects the other models or recovers from an OOM kill
- **Severity**: P2 · **Confidence**: PLAUSIBLE (gate logic CONFIRMED; absence of other protections CONFIRMED by grep; the kill itself needs a device) · **Effort**: M
- **Location**: `Utils/PlatformCapabilities.swift:17-35`; `MLXOnDeviceModels.swift:111-113`; `Views/OnDeviceLLMSettingsView.swift:268-278`; `MLXOnDeviceClient.swift:532-535`
- **Scenario**: Verified: the gate reads installed memory (`ProcessInfo.processInfo.physicalMemory`), requires `isiOSAppOnMac`, is covered by `testMedGemma27BChatRequiresMacWithAtLeast24GiBOfInstalledMemory`, and is enforced in four places (catalog, `startDownload`, `performLoadModel`, UI list). Gaps: (a) MediPhi (2.15 GB) and Qwen (3.03 GB) are offered on every device; the iOS 26 target admits 4 GB-class phones (verify against Apple's iOS 26 compatibility list), where weights plus KV cache plus activations are a jetsam risk. (b) The context slider allows 64K tokens with only "uses more memory" as warning; the KV cache grows with it. (c) No `didReceiveMemoryWarning` observer and no `os_proc_available_memory` pre-check exist. (d) If a load or long generation does get the process killed, the selection and settings persist; the same action next launch repeats the kill, and `AppLog`'s unclean-shutdown flag feeds no logic. A mid-reply kill leaves a persisted user message with no reply and no half-written assistant message (the assistant message is only written in `onComplete`), which is the acceptable outcome. (e) At the 24 GiB boundary the 16 GB weights plus 4–8 GB OS leaves little room; no headroom check at load.
- **Evidence**:
  ```swift
  // MLXOnDeviceModels.swift:111-113
  public var isAvailable: Bool {
      id != Self.medGemma27BTextIT4Bit.id || PlatformCapabilities.supportsMedGemma27BChat
  }
  ```
- **Fix**: add per-model `minimumPhysicalMemoryBytes` (and cap the context slider by it); write a "loading model X" marker before `loadContainer` and clear it after; if present at launch, refuse to autoload and show a recovery prompt; observe memory warnings and unload.
- **Blast radius**: model catalog, settings, client load path.
- **Verification**: device matrix (4/6/8 GB phones), 64K context with a long prompt, watch for jetsam in Console; kill during load and relaunch.

### WS-12-09 — `MLXGPUGate` (WS-04-15) is worse than P3: the gate is held across network I/O in model load, and title generation is uncapped
- **Severity**: P2 (WS-04-15 filed P3) · **Confidence**: PLAUSIBLE (hold-across-load CONFIRMED by source; real-world stall duration needs a device) · **Effort**: M
- **Location**: `MLXOnDeviceClient.swift:174-178`, `:494-497`, `:605-608`; `Managers/AIChatManager.swift:304-314`
- **Scenario**: WS-04-15 requires "a GPU-level hang" for the gate to wedge. But `loadModel`, `testConnection`, `sendMessage` and `sendStreamingChatMessage` all call `performLoadModel()` while holding the gate, and (WS-12-01) the load performs HTTP calls to huggingface.co and possibly a multi-GB re-download. On a captive-portal or half-dead network the HEAD requests wait for URLSession timeouts, a re-download can run minutes; every other MLX operation, including `suspendForBackground` and VLM extraction, queues behind it, and WS-03-08 shows waiters ignore cancellation. Separately, title generation calls `sendMessage` which uses the user's full `maxTokens` (up to 4,096) with no title cap, so a rambling small model holds the gate for the whole budget right after the first reply, delaying the user's next question.
- **Evidence**:
  ```swift
  // :174-178
  await MLXGPUGate.shared.acquire()
  defer { MLXGPUGate.shared.release() }
  do { try await performLoadModel()
  ```
- **Fix**: remove network from the load path (WS-12-01); add cancellation and a timeout to `acquire`; pass `maxTokensOverride: 32` for titles.
- **Blast radius**: all MLX operations.
- **Verification**: device with a throttled/black-holed route to huggingface.co: confirm chat load hangs today; assert title generation stops within 32 tokens.

### WS-12-10 — Storage honesty: `StorageUsageView` omits models entirely, and models live in purgeable Caches
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Views/StorageUsageView.swift:158-166`; `MLXModelDownloadManager.swift:949-958`; `Views/OnDeviceLLMSettingsView.swift:362-366`
- **Scenario**: "Total Used" sums health data, documents, thumbnails, chat and exports/logs only; downloaded models (2–16 GB, the biggest thing the app stores) are absent, so the screen under-reports by orders of magnitude and "Clear Cache" does nothing for them. The only place a size appears is the On-Device AI screen, which also hides partials (WS-12-05). Models sit in `Library/Caches`, which iOS may purge when space is low; `refreshModelStatus` at launch notices missing files and clears the Downloaded state, but the user simply finds a 16 GB model gone with no explanation. Deletion itself is thorough: `deleteModel` removes the snapshot directory and the Hub blob stores in all candidate roots (`:312-331`).
- **Evidence**:
  ```swift
  cacheSize: usage.exportsSize + usage.logsSize,
  ```
- **Fix**: add an "On-device models" row from `MLXModelDownloadManager`; consider `Application Support` with `isExcludedFromBackup` so the OS cannot purge; message the re-download need.
- **Blast radius**: storage view, download manager paths.
- **Verification**: download a model, open Storage Usage, compare with Settings > General > iPhone Storage.

### WS-12-11 — App Store: the app is functional without a model, but the download, its disclosure and the offline claim need reviewer notes
- **Severity**: P2 · **Confidence**: PLAUSIBLE (guideline text fetched; Apple's judgment is not predictable) · **Effort**: S
- **Location**: `Views/OnDeviceLLMSettingsView.swift:75`, `:124-126`; `Managers/SettingsManager.swift:98`; `MLXOnDeviceLLM/MLXModelDownloadManager.swift:469-475`
- **Scenario**: Reviewers install a build whose default provider is on-device (`aiProvider = .onDeviceLLM`) but with the feature toggle off and no model, so chat is unavailable on first run. Health records, vitals, documents, native OCR import (PDFKit + Vision) and exports work with no model, so the app is not a shell; this is the central point for 4.2/2.1 and should be stated. To evaluate chat, the reviewer must enable the toggle and download 2.15 GB or 3.03 GB, which is a real obstacle. Guideline text fetched 2026-10-22 from `https://developer.apple.com/app-store/review/guidelines/` (no "last updated" date shown on the page): 4.2.3(ii) "If your app needs to download additional resources in order to function on initial launch, disclose the size of the download and prompt users before doing so"; 2.3.1(a) new functionality must be described with specificity in Notes for Review; 5.1.2(i) disclose third-party sharing; 2.5.2 forbids downloading *code* that changes features, model weights are data, but the jinja chat templates are interpreted, so describe them. The privacy policy currently omits Hugging Face (WS-07 C7), and the UI claims "No internet required after downloading" which WS-12-01 may falsify.
- **Fix**: see reviewer notes below; add a size/network confirmation (WS-12-07); fix the offline path (WS-12-01); add the Hugging Face disclosure to the privacy policy and App Privacy answers.
- **Blast radius**: WS-13 submission package, `PrivacyPolicyView`, first-run UX.
- **Verification**: a clean-device walkthrough with reviewer notes, including airplane-mode chat after one download.

**Recommended reviewer notes (feeds WS-13)**: (1) "Core features (health records, vitals, document import with on-device OCR, export) work with no download. AI chat is optional." (2) "To test AI chat: Settings > On-Device AI > enable > download 'MediPhi Instruct' (2.15 GB over Wi-Fi, ~10 min). The download comes from huggingface.co and contains model weights and tokenizer/template files only, no executable code." (3) "Cloud AI (AWS Bedrock, OpenAI-compatible) is off by default; no credentials needed to review." (4) "MedGemma 27B appears only on Macs with >= 24 GB RAM (iOS app on Mac)." (5) Provide a short screen recording of a completed chat in case the reviewer's network is slow.

### WS-12-12 — Deleting a model does not unload or deselect it
- **Severity**: P3 · **Confidence**: CONFIRMED (no unload call) · **Effort**: S
- **Location**: `MLXModelDownloadManager.swift:312-331`; `Views/OnDeviceLLMSettingsView.swift:46-52`
- **Scenario**: Delete the currently loaded model from the menu: files go, the resident container keeps answering (and holding 2–3 GB of RAM) until backgrounding; `selectedModelId` still points at a model that is not downloaded, so the next load throws `modelNotDownloaded`. Failures in `removeItem` are only logged and the row immediately re-validates as downloaded.
- **Fix**: call `SettingsManager.shared.invalidateClients()` and fall back to another downloaded model; surface deletion errors.
- **Blast radius**: settings view.
- **Verification**: load model, delete it, send a message.

### WS-12-13 — Dead preload and unreachable `modelLoadFailed`
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `Managers/SettingsManager.swift:611-642`; `MLXOnDeviceLLM/MLXOnDeviceResponse.swift:45`, `:82`
- **Scenario**: `preloadOnDeviceLLMIfNeeded` has no callers (grep over the repo), so the "ready when chat opens" behaviour does not exist; the first chat pays the load. `MLXOnDeviceError.modelLoadFailed` is never thrown, so its recovery text ("re-downloading the model") never appears; a corrupt model's load error surfaces as a raw library message with no repair path other than manual delete.
- **Fix**: remove the preload or wire it (with the crash marker of WS-12-08); wrap `loadContainer` errors in `modelLoadFailed`.
- **Blast radius**: none functional.
- **Verification**: grep; unit test the error mapping.

### WS-12-14 — Progress monitor walks the model directories every second for a value it then ignores
- **Severity**: P3 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `MLXModelDownloadManager.swift:749-755`, `:1010-1021`
- **Scenario**: `measureDownloadedBytes` enumerates two directory trees (blobs plus snapshot, hidden files included) every second for the entire download; once `progressBox` reports totals, `cachedBytes` is unused. Cheap per call, but wasteful for a long download on battery.
- **Fix**: compute it only while `totalUnitCount == 0`.
- **Blast radius**: download manager only.
- **Verification**: Instruments file-system trace during a download.

## WS-03-03 verification (backgrounding while generating)

- **(a) Does any background path cancel?** No. `HealthAppApp.handleScenePhaseChange(.background)` (`HealthAppApp.swift:332-336`) only writes the clean-shutdown marker and starts a `Task` calling `suspendOnDeviceLLMForBackground()`. That calls `suspendForBackground()` (`MLXOnDeviceClient.swift:596-610`) which sets a flag and then `await MLXGPUGate.shared.acquire()`: it *queues behind* an in-flight reply because `sendStreamingChatMessage` holds the gate for the whole generation (`:280-281`). Nothing cancels the stream, the flag `isSuspendedForBackground` is read nowhere else, and `.inactive` is ignored. The gate is only released at the end of the reply, then the model unloads, so any GPU work for the remainder of the reply is issued while backgrounded. The VLM page loop is the same shape (`:803-838`, one gate hold per page).
- **(b) Background declarations?** None. grep over the app source, `Info.plist` and `project.pbxproj` for `UIBackgroundModes`, `BGTaskScheduler`, `beginBackgroundTask`, `URLSessionConfiguration.background` returns nothing (consistent with WS-04). The only related entitlement is `kernel.increased-memory-limit`.
- **(c) Device test needed.** Physical iPhone (and a second run on an 4–6 GB model), Release build, MediPhi selected, `maxTokens = 4096`, logging at `.mlx`. Steps: ask for a long answer; after the first tokens appear, press Home. Variations: wait 5, 30 and 120 s before returning; repeat with a Control Center or app-switcher pull (the `.inactive` case); repeat during on-device document extraction with Qwen over a 6-page PDF; repeat on iPad in Split View (app visible but not key). Capture: Xcode device console for `Insufficient Permission (to submit GPU work from background)` / `kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted` or an `abort()` in an MLX frame; `.ips` crash logs in Settings > Privacy > Analytics; whether `[MLXClient] Suspended for background` is logged before or after the last chunk; whether the reply persists on return. Pass: no crash, generation stops or pauses cleanly, the partial reply is kept, the model reloads. Fail: a crash log with an MLX/Metal frame while the app is in the background. Do not upgrade to CONFIRMED without that run.

## Structural risks (max 5 bullets)

- The app owns the *download* but a third-party library still owns the *load*; the two disagree about what a model directory must contain (WS-12-01). Pick one owner.
- Model identity is a mutable branch name on third-party repos; integrity, reproducibility and clinical safety review all depend on pinning.
- All MLX behaviour (gate, eviction, background, load, memory) has zero automated coverage and is invisible on the simulator; the beta needs a physical-device checklist.
- The on-device safety rules live in a prompt that is subject to window eviction; safety-critical constraints should be re-asserted per turn and enforced on output where possible.
- The download is a foreground, single-session, retry-limited operation for a payload that takes tens of minutes on real networks.

## Machine-readable summary
```json
[
  {"id":"WS-12-01","title":"Model load re-contacts Hugging Face every time, needs Hub metadata the custom downloader never writes (offline-first-load and MedGemma offline failures), and may silently re-download shards under the GPU gate","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:545","HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:491"],"effort":"M","area":"mlx-lifecycle"},
  {"id":"WS-12-02","title":"On-device context budget guarantees KV-window overflow; sliding window evicts persona, patient data and compactChatRules before conversation turns","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:640","HealthApp/HealthApp/Utils/ConversationContextBuilder.swift:17","HealthApp/HealthApp/Managers/AIChatManager.swift:43"],"effort":"M","area":"mlx-lifecycle"},
  {"id":"WS-12-03","title":"A 16 GB download is wiped after three interruptions; backgrounding spends the shared retry budget","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:836","HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:1125"],"effort":"M","area":"mlx-lifecycle"},
  {"id":"WS-12-04","title":"No hash or revision pin; usable means config plus shard names, tokenizer not required","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:1093","HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:683"],"effort":"M","area":"mlx-lifecycle"},
  {"id":"WS-12-05","title":"Killing the app mid-download strands up to 16 GB that no UI counts or reclaims","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:374","HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:1117"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-06","title":"No free-space preflight; a full disk also starves the health database","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:142"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-07","title":"Multi-GB download starts on cellular on one tap, overriding Low Data Mode","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:118","HealthApp/HealthApp/Views/OnDeviceLLMSettingsView.swift:124"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-08","title":"MedGemma memory gate sound; smaller models ungated, 64K context slider, no OOM recovery marker","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Utils/PlatformCapabilities.swift:17","HealthApp/HealthApp/Views/OnDeviceLLMSettingsView.swift:268"],"effort":"M","area":"mlx-lifecycle"},
  {"id":"WS-12-09","title":"MLXGPUGate held across network I/O in model load; title generation uncapped (escalates WS-04-15)","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift:174","HealthApp/HealthApp/Managers/AIChatManager.swift:314"],"effort":"M","area":"mlx-lifecycle"},
  {"id":"WS-12-10","title":"StorageUsageView omits models; models live in purgeable Caches","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/StorageUsageView.swift:158","HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:949"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-11","title":"App Store: functional without model but download needs size/network prompt, reviewer notes and HF disclosure","severity":"P2","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Views/OnDeviceLLMSettingsView.swift:75","HealthApp/HealthApp/Managers/SettingsManager.swift:98"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-12","title":"Deleting a model does not unload or deselect it","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:312"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-13","title":"Dead preloadOnDeviceLLMIfNeeded and unreachable modelLoadFailed","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/SettingsManager.swift:611","HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceResponse.swift:45"],"effort":"S","area":"mlx-lifecycle"},
  {"id":"WS-12-14","title":"Progress monitor enumerates model directories every second for an ignored value","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/MLXOnDeviceLLM/MLXModelDownloadManager.swift:749"],"effort":"S","area":"mlx-lifecycle"}
]
```

---

## Orchestrator verification note (2026-10-22)

Three claims in this file were re-checked against source by the orchestrating session.

**Confirmed as filed:**
- `MLXModelDownloadManager.swift:118-119` sets `allowsExpensiveNetworkAccess = true` and
  `allowsConstrainedNetworkAccess = true`, so a multi-gigabyte download proceeds on
  cellular and overrides Low Data Mode (WS-12-07).
- `RotatingKVCache(maxSize: maxKVSize, keep: 4)` at `mlx-swift-lm`
  `MLXLMCommon/LanguageModel.swift:226` and `KVCache.swift:1503`, with
  `compactChatRules` appended as the last section of the system block
  (`MLXOnDeviceClient.swift:645`). The rules sit in the head region beyond the kept-4
  window, so they are evicted as context rotates (WS-12-02). Mechanism confirmed;
  effect on answer quality still needs a device.
- Every model load reaches the network while online: `LLMModelFactory.swift:491` calls
  `downloadModel`, which calls `hub.snapshot(from:revision:matching:)`
  (`MLXLMCommon/Load.swift:21-37`). The per-load Hugging Face contact in WS-12-01 is real,
  and it is not in WS-07's egress inventory, which covers only the one-time download.

**Corrected — WS-12-01 is overstated on the offline point.** `downloadModel` has two
explicit fallbacks to the local directory (`Load.swift:41-55`): one on
`Hub.HubClientError.authorizationRequired`, and one when the error is
`NSURLErrorNotConnectedToInternet` (-1009). So a genuine airplane-mode load *does* fall
back to local files rather than failing, and "the first load of a downloaded model has to
be online" is not supported as written.

The real defect is narrower and still worth fixing: **only -1009 is handled.** A captive
portal, a DNS failure, a timeout, or an HTTP error from the Hub is not -1009, so it
propagates and the load fails — on a feature whose whole purpose is to work without the
network. The separate "Metadata not available" claim (that the app's custom downloader
never writes Hub `.metadata` files, so a downstream tokenizer load throws) was **not**
verified here and should be treated as PLAUSIBLE pending a device test.
