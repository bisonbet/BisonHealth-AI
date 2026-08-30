# Pre-Beta Deep Review — AI Discussion Mechanism & Document Import

Date: 2026-08-30 · Method: 4 parallel fresh-context reviewers (chat-state, chat-providers, doc-import, doc-persist-ui), ~15k lines across both mechanisms, all top findings re-verified against source by the lead reviewer.

**Verdict: Not beta-ready yet.** 2 P0 and 17 unique P1 findings, several of which will be hit by nearly every beta user (streaming dies after the first reply; reprocessing any imported lab report always fails; sharing a document produces an unopenable file; every non-ASCII character in streamed AI replies is corrupted).

---

## P0 — Release blockers

### P0-1. Crash: PDF with an unloadable page → array index out of range during import
`Services/NativeDocumentExtractor.swift:309, 359`

Loop 1 skips pages where `pdfDocument.page(at: i)` returns nil (`guard ... else { continue }`), so `pdfKitPages` ends up shorter than `pageCount`. Loop 2 (OCR) still indexes `finalPages[pageIndex]` over `0..<pageCount` — if a *middle* page fails to load, every subsequent page write/read is out of bounds → crash mid-import.

Damaged/faxed/EHR-exported PDFs hit this regularly. Fix: index `finalPages` by a parallel dictionary or compact the loops to the same surviving-page list.

### P0-2. PHI written to durable plaintext logs (release builds)
`MLXOnDeviceLLM/MLXOnDeviceClient.swift:834` (+ corroborating leaks below)

`mergePageJSON` logs the last 240 chars of raw VLM transcription when JSON parsing fails — the *routine* fallback path for a 4B model:
```swift
let tail = String(response.suffix(240))...
AppLog.shared.mlx("[MLXClient] Unparseable VLM page \(pageNumber) output ends: …\(tail)", level: .warning)
```
`AppLog` persists `.warning` to `Logs/app-<date>.log` in release (`minimumLogLevel = .info`, AppLog.swift:119), plaintext, and "Export Support Logs" ships this file. Lab values, units, physician names, dates are PHI. `redactForSupport` regexes don't cover lab text.

Corroborating PHI-to-log leaks (same class of issue):
- `Managers/AIChatManager.swift:282, 285` — logs AI-generated conversation titles derived from user health messages.
- `ContentView.swift:1002` — logs extracted lab values; `ContentView.swift:926` logs full import URLs (filenames often contain patient names).
- `DocumentProcessor.swift:1501, 1516` — patient-identifying filenames in lock-screen notifications.

Fix class: log lengths/status codes only; never raw model output, titles, values, or filenames. Consider gating all PHI-adjacent logging behind `#if DEBUG`.

---

## P1 — AI interactive discussion

### P1-1. Live streaming dies after the first response in a session
`Managers/AIChatManager.swift:563–609`

`updateStreamingMessage` guards `if streamingUpdateTask != nil { return }`. `finalizeStreamingMessage` cancels the sleeping throttle task; the `catch is CancellationError { // Expected }` branch **never clears `streamingUpdateTask`**. From then on the property holds a dead task forever: every later turn stores chunks in `pendingStreamingContent` that are never applied. All subsequent responses render blank until completion. This hits *every* multi-turn streaming session.

### P1-2. Switching conversations mid-stream is repeatedly undone
`Managers/AIChatManager.swift:585, 615`

Both the throttle tick and finalize unconditionally execute `self.currentConversation = self.conversations[conversationIndex]` for the *streaming* conversation. If the user opens another conversation while a reply streams, the UI snaps back ~15×/sec until the stream ends (ChatDetailView renders `chatManager.currentConversation`). Fix: only assign when the ids already match.

### P1-3. Every non-ASCII character in a streamed reply is corrupted (mojibake), then saved
`Services/OpenAICompatibleClient.swift:684`

```swift
for try await byte in bytes { let char = Character(UnicodeScalar(byte)) ... }
... dataContent.data(using: .utf8)
```
Byte-wise Latin-1 transcoding then UTF-8 re-encoding: `—` becomes `â€”`, `°` becomes `Â°`. Health replies routinely contain `°`, `±`, `µ`, accents. The corrupted text is persisted to the chat DB. `AIResponseCleaner.swift:126` patches 11 of these sequences downstream — a symptom patch, not a fix. Fix: decode with `bytes.lines` (UTF-8) or accumulate `Data`. (Bedrock's stream parser should be checked for the same pattern.)

### P1-4. Global error-alert "Retry" is a silent no-op
`Managers/AIChatManager.swift:474` + `Models/ChatModels.swift:129`

The `retryAction` closure captures the original `userMessage` struct (status nil). `markFailed` mutates the array copy, not the captured value, so `retryFailedMessage`'s `guard message.canRetry` (requires `status == .failed || isError`) always fails → tap Retry → alert dismisses, nothing happens, only a debug log. The per-bubble retry button works because it passes the mutated array copy.

### P1-5. Privacy opt-outs silently revert to "include everything"
`Database/DatabaseManager+Chat.swift:20–23, 115–117` + `Models/ChatModels.swift:53`

`saveConversation`/`updateConversation` persist `includedHealthDataTypes`, tags, archive flag — but **never** `includedPersonalInfoCategories`. The decoder defaults the missing field to `Set(PersonalInfoCategory.allCases)`. Any user who excludes e.g. medications/mental-health info from AI context gets it re-included after restart. Privacy-relevant: fix before beta.

---

## P1 — Document import & persistence

### P1-6. "Reprocess Document" on an imported lab report deterministically fails (×3 retries, paid cloud passes) and marks it Failed
`Services/DocumentProcessor.swift:438` → `Managers/HealthDataManager.swift:242, 375`

`linkExtractedDataToDocument` unconditionally calls `addBloodTest` for the same `source_document_id`; the duplicate check throws `"This blood test has already been imported from this document"`; the generic catch re-runs the **entire** pipeline (OCR + AI extraction) up to `maxRetryAttempts`, then flips the document to `.failed`. Every successfully imported lab report that still exists in Records ends up Failed after a reprocess tap.

### P1-7. Reprocess/retry wipes user-entered metadata and the AI-context toggle
`Services/DocumentProcessor.swift:337–360` + `Database/DatabaseManager+MedicalDocuments.swift:19–44`

The processing pass constructs a full `MedicalDocument(... documentDate: extractionResult.documentDate, providerName: ..., includeInAIContext: false, contextPriority: 3, lastEditedAt: nil ...)` and saves via `insert(or: .replace)` — a full-column overwrite (unlike the merging `saveDocument`). Reprocessing a document the user edited resets date/provider (often to nil), clears `lastEditedAt`, and silently drops it **out of AI chat context**.

### P1-8. Cancel is never propagated: Pause/Clear silently restart work; delete mid-processing resurrects the row
`Services/DocumentProcessor.swift:491–501` (catch block has no `Task.isCancelled`/`CancellationError` check) + `Managers/DocumentManager.swift:383–391`

- Pause/Clear Queue cancels tasks, but the in-flight item's `CancellationError` lands in the generic catch → auto re-queue after backoff → processing resumes.
- Deleting a document mid-extraction: Vision OCR has no cancel checkpoint; when the task finishes it does `saveMedicalDocument` (INSERT OR REPLACE) → recreates the just-deleted row, with `filePath` pointing at the deleted file. The "deleted" document reappears (broken preview), and its blood test still imports into Records.

### P1-9. Documents stuck in `.processing` forever after an interrupted run
`Services/DocumentProcessor.swift` (no recovery path; only writes are 281/340/390)

If the app is killed mid-processing (force-quit, crash, iOS suspension), rows stay `.processing` forever; there is no startup sweep resetting them to `.pending`/`.failed`, and the detail view only offers Retry for `.failed`. Users see a permanent spinner with no path forward.

### P1-10. Share hands out the encrypted file
`Views/DocumentDetailView.swift:99` + `Utils/FileSystemManager.swift:137`

Storage writes AES-GCM ciphertext to `filePath`. QuickLook decrypts to a temp file first; `DocumentShareSheet(items: [document.filePath])` does not — AirDrop/Save-to-Files recipients get an unopenable `*.pdf` ciphertext. Same for `DocumentManager.shareDocument`/`shareSelectedDocuments`.

### P1-11. "Export PDF report" produces blank pages
`Utils/DocumentExporter.swift:262–320`

`createPersonalInfoPage`/`createBloodTestPages`/`createDocumentsSummaryPage` return bare `PDFPage()` with no content; even the title page draws into a `UIGraphicsImageRenderer` image that is then discarded (`_ = image`). Comments admit "simplified version for demonstration". The export feature is non-functional.

### P1-12. Documents table stores PHI in plaintext while every sibling table encrypts
`Database/DatabaseManager.swift:68–91`

`extracted_text`, `notes`, `provider_name`, `file_name` are plain columns; `health_data` uses `encrypted_data`, chat messages encrypt content ("// Encrypted"), preps encrypt. Either the app's "local and encrypted" promise is wrong or this table was missed. Decide and align before beta (this is near-P0 for a health app's privacy posture).

### P1-13. Review-needed lab values live in one in-memory slot — concurrent imports or restart lose them permanently
`Services/DocumentProcessor.swift:897` (single `pendingImportReview`; `maxConcurrentProcessing = 3`)

Doc 1's review sheet is showing; doc 2 finishes with uncertain values → overwrites the slot → ContentView re-binds to doc 2 → doc 1's values are never persisted anywhere. Force-quit while a review is pending = same loss. (Genetic review has the same single-slot pattern.)

### P1-14. Every processed document's `thumbnail_path` is overwritten to NULL
`Services/DocumentProcessor.swift:339` + `DatabaseManager+MedicalDocuments.swift:8`

The full-column INSERT OR REPLACE writes `thumbnailPath` from the queue item (nil by then), clobbering thumbnails written by the async thumbnailer. Thumbnails never display post-processing.

### P1-15. Multi-file import: only the first selected document is processed
`ContentView.swift:930–936`

`importedDocs.first` gets the category selector; the rest never get a category and never enter processing — they sit unprocessed in the library. Verify whether `importDocuments` queues them; as written, a user importing 5 lab PDFs gets 1 processed.

---

## P2 — Real but lower priority (fix after beta or before if cheap)

| # | Location | Issue |
|---|----------|-------|
| 1 | `AIChatManager.swift:376` + `:654/718/784/851` | Clearing messages mid-stream lets the late completion re-add the assistant reply; failed streams leave an empty placeholder message |
| 2 | `AIChatManager.swift:466` | Failed-send status is memory-only; after restart failed messages look successfully sent |
| 3 | `AIChatManager.swift:867` | Retry path sends with zero conversation history (fresh context only) and no send-in-flight guard |
| 4 | `AIResponseCleaner.swift:142` | Whitespace collapse flattens legitimate markdown structure *before persistence* (data-destructive cleaning) |
| 5 | `DatabaseManager+Chat.swift:33` | Startup eagerly decrypts every message of every conversation on the main actor and keeps it in memory |
| 6 | `DatabaseManager+Chat.swift:262` | DB connection used from a background queue despite MainActor isolation (works via SQLite FULLMUTEX; violates the manager's contract) |
| 7 | `DatabaseManager+Chat.swift` (all catches) | Arbitrary SQLite errors re-laundered as `encryptionFailed`/`decryptionFailed` (also `DatabaseManager+Documents.swift:65`) — masks real failures, hurts diagnostics |
| 8 | `ConversationContextBuilder.swift:139` | History trimming drops an oversized newer message but keeps older ones → non-contiguous history sent to the model |
| 9 | `MLXOnDeviceClient.swift:282` | MLX KV-cache session rebuilt every turn because health context embeds a per-second timestamp |
| 10 | `MLXOnDeviceClient.swift:356` | Full-text `cleanConversational` on every token chunk on the main actor — O(n²) UI jank on long replies |
| 11 | `MLXOnDeviceClient.swift:366–372` | Mid-stream failure leaves the MLX ChatSession (KV cache) dirty → corrupted context for subsequent turns |
| 12 | `OpenAICompatibleClient.swift:697` | SSE parser requires `"data: "` with trailing space (spec allows `data:`) |
| 13 | `OpenAICompatibleClient.swift:746-752`, `BedrockClient.swift:409-452` | Empty streamed completion saved as a blank assistant message with no error surfaced |
| 14 | `BedrockClient.swift:181–193` | `AWSBedrockConfig.timeout` is dead config — SDK client built with no timeout (infinite hang possible) |
| 15 | `MLXModelDownloadManager.swift:557–683` | Model weights size-verified but never content-verified (no checksum) |
| 16 | `NetworkManager.swift:63–125` | Two helper methods are latent traps (crash / permanent hang); currently uncalled — delete or fix |
| 17 | `HealthDataManager.swift:372` | Early `return` (not `continue`) on a pending-review blood test silently drops the rest of the extracted items (incl. genetic refresh) |
| 18 | `NativeDocumentExtractor.swift:309/341/359` | (root cause shared with P0-1) array/page index misalignment on malformed PDFs |
| 19 | `DocumentImporter.swift:63` + `ContentView.swift:926` | Patient-identifying filenames leak past redaction into plaintext logs |
| 20 | `ContentView.swift:587` vs `DocumentImporter.swift:342` vs `NativeDocumentExtractor.swift:244` | Picker/importer/extractor file-type contracts disagree (e.g., one accepts types another rejects) |
| 21 | `FileSystemManager.swift:343` | `findDocumentByFileName` returns first fuzzy match — same-named docs can cross-link after a container path change; also rebinds a document to another document's file |
| 22 | `DocumentProcessor.swift:1529` | "Processing Complete" notification has an inverted guard (notifies on empty queue / vice versa) |
| 23 | `FileSystemManager.swift` (@MainActor) | Whole-file crypto + vision rasterization run on the main thread |
| 24 | `DocumentProcessor.swift:216` | No dedupe in `addToQueue`; `processingTasks[id]` silently overwritten |
| 25 | `DocumentImporter.swift:140-156` + `DatabaseManager+Documents.swift:337` | Thumbnail-completion save races processing and resets status |
| 26 | `DocumentDetailView.swift:142-148` | Delete failure looks like success to the user |
| 27 | `MedicalDocumentDetailViewModel.swift:110-119` | Edits save fire-and-forget with no user-visible error |
| 28 | `BloodTestImportReviewView.swift:74-75` + `ContentView.swift:1057-1071` | Canceling the import review permanently discards auto-accepted lab values |
| 29 | `DatabaseManager.swift:447-461` | Migration v4 = ten sequential ALTERs, no transaction — crash mid-migration bricks every subsequent launch (duplicate-column error on retry). Consider wrapping migrations in a transaction |
| 30 | `DatabaseManager+Documents.swift:73-91` | No LIMIT/pagination; full rows decoded at launch |
| 31 | `DocumentProcessor.swift:539-540` | Synchronous read+decrypt of up to 50 MB on the main actor |
| 32 | `MedicalDocumentExtractor.swift:33` | Unquoted filenames escape log redaction patterns |

---

## Verified fine (reviewers cleared these — useful confidence)

- User message is persisted **before** the network call (AIChatManager:446).
- Deleting a conversation mid-stream is safe — FK cascade + `PRAGMA foreign_keys = ON`; the late insert fails cleanly.
- Document context is re-built from the DB immediately before every send — no stale-context-after-document-change bug.
- MLX session keyed by conversationId — no cross-conversation context bleed.
- SSE keep-alives/`[DONE]`/CRLF handled; strict JSON decode failures fall back to flexible parsers (no crash).
- API keys never logged ("(configured)" only); Keychain writes are verified after save.
- Security-scoped bookmarks balanced per-URL with `defer`; UUID-prefixed filenames prevent collisions.
- GPU gate acquire/release pairs correct on all paths, including the per-page VLM loop.
- Page-at-a-time rasterization keeps on-device VLM memory bounded; OCR runs off the main actor.
- `saveDocument`'s merge path protects import-time fields (unlike `saveMedicalDocument` — see P1-7).
- No reachable force-unwraps/`try!`/`fatalError` in the chat seam; guarded ones in SettingsManager.

## Suggested fix order for beta

1. **P0-1** index-out-of-range crash (small, contained fix in NativeDocumentExtractor).
2. **P0-2 + PHI-log family** (P1 titles/values/filenames/notifications) — one logging-hardening pass.
3. **P1-1 / P1-2** streaming throttle task lifecycle + `currentConversation` guard (same function, fix together).
4. **P1-3** UTF-8 SSE decoding (OpenAI + audit Bedrock).
5. **P1-8 / P1-9** cancellation checks in `processQueueItem` catch + startup `.processing` sweep (same area).
6. **P1-6 / P1-7 / P1-14** reprocess flow: skip/dedupe relinking, merge-preserve user fields, keep thumbnail path (all in the save path).
7. **P1-5** persist `includedPersonalInfoCategories` (one column + two writes + decoder).
8. **P1-4** retry closure should pass the mutated message (or re-lookup by id).
9. **P1-10 / P1-11** share decrypt-to-temp + real PDF export pages (or hide both buttons for beta).
10. **P1-12** decide plaintext-vs-encrypted documents table; **P1-15** decide multi-import UX; **P1-13** persist review state or queue reviews.

---

*Appendix: full lane reports preserved in the subagent run transcripts; raw copies at /tmp/review-{chat-state,chat-providers,doc-import,doc-persist-ui}.md (session-temp).*

---

# Fix Status — 2026-08-30 (post-review fix pass)

**Validation: full suite green — 285 tests passed, 0 failed (275 baseline + 10 new regression tests in PreBetaRegressionTests.swift). Zero build warnings.**

## Fixed (all P0 + all P1 + 27 P2s)

| Finding | Fix |
|---|---|
| P0-1 PDF page-index crash | Dead pages now append an empty PageText, keeping indices aligned with pageCount (NativeDocumentExtractor) |
| P0-2 PHI in logs | MLX transcription tail logs length only; AI titles never logged; 9 unquoted-filename log sites quoted so redaction catches them; lock-screen notifications genericized |
| P1-1 streaming dies after first reply | Throttle task slot cleared on cancellation; entry guard also ignores cancelled-but-uncollected tasks |
| P1-2 conversation snap-back | Throttle tick + finalize + failure paths only refresh currentConversation when the ids match |
| P1-3 SSE mojibake | bytes.lines UTF-8 decoding (OpenAI); extracted testable sseDataPayload also accepts data: without space |
| P1-4 retry alert no-op | retryFailedMessage re-resolves current message state from the conversation + isSendingMessage guard |
| P1-5 privacy opt-outs revert | New included_personal_info_categories column (DB v11), persisted in save/update, decoded in builder |
| P1-6 reprocess deterministically fails | linkExtractedDataToDocument treats duplicate-import validationFailed as a skip, not a document failure |
| P1-7 reprocess wipes metadata | Processing pass merges existing row fields (date/provider/AI-context/priority/lastEditedAt/tags/notes) |
| P1-8 cancel not propagated | Cancellation classified in processQueueItem catch (restore .pending, no retry); Task.checkCancellation before any post-OCR writes |
| P1-9 stuck .processing forever | Startup sweep resets interrupted .processing rows to .failed (Retry path available) |
| P1-10 share = encrypted file | Share decrypts to a temp copy, cleaned up on sheet dismiss |
| P1-11 blank PDF export | Real UIGraphicsPDFRenderer pagination with per-block page breaks (+ explicit first beginPage — caught by the new test) |
| P1-12 PHI plaintext in documents table | file_name/notes/provider_name/extracted_text + extracted_data/raw_docling_output/extracted_sections + chat titles now AES-GCM at rest (DB v11 migration encrypts existing rows); search/provider filters moved in-memory |
| P1-13 review-slot overwrite | pendingImportReview is now a queue; concurrent reviews queue behind the presented one; Cancel discards cleanly; sheet not swipe-dismissable |
| P1-14 thumbnails clobbered | Preserved via existing-row merge + dedicated updateDocumentThumbnailPath (also fixes the thumbnail/status race) |
| P1-15 multi-file import | Category selector queues ALL imported docs, presented sequentially |
| P2s | clear-mid-stream guard on all 3 onComplete paths; empty-placeholder cleanup on failed sends; non-streaming sends now carry full conversation history (interface gained conversationHistory param, OpenAI uses trimmed history, Bedrock/MLX use transcript); failed status persisted (is_error) so retry survives restart; 19 laundered DB catches now log the real error; migrations atomic + per-step version bump (bricks no more); return→continue in link loop; inverted completion-notification guard; addToQueue dedupe; exact-match file recovery (no cross-linking); delete failure surfaced in UI; ViewModel save errors surfaced; context trimming keeps contiguous suffix; cleaner preserves markdown indentation; day-precision context timestamp (MLX KV-cache reuse); MLX per-chunk clean time-gated; MLX session invalidated on mid-stream error; empty streamed completions throw (OpenAI + Bedrock); two dead NetworkManager traps deleted; picker types aligned with importer; Bedrock timeout documented as advisory |

## Deliberately deferred (documented with ponytail: comments at the sites)

- Pending import reviews are memory-only — force-quit during the review sheet still loses un-reviewed groups (persist payload in a documents column if beta users hit it).
- Whole-file crypto + vision rasterization run on the main actor (bounded by 50MB cap; move off-main if profiling shows jank).
- Startup eagerly decrypts all conversations (fine at beta scale; lazy-load if launch slows).
- DB v11 PHI encryption means SQL search moved in-memory — O(all-documents) scan, fine at beta scale.
- MLX model downloads are size-verified only, no checksum.
- No row pagination yet.

## Note on migration risk

DB v11 encrypts existing rows in a transaction. Beta devices on v10 upgrade on first launch. **Test one real v10 → v11 upgrade on a seeded device before shipping** (the migration is transactional, but see it run once).
