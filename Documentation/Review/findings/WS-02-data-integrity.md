# WS-02 — Data integrity, migrations & encryption at rest

- **Agent / model**: Claude Sonnet 5.5 (`claude-sonnet-5-5`), read-only review agent
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (working tree has unrelated doc-only modifications under `Documentation/Review/`)
- **Scope actually covered**: all 8 files in `HealthApp/HealthApp/Database/` read in full (`DatabaseManager.swift`, `+HealthData`, `+Documents`, `+Chat`, `+MedicalDocuments`, `+AppSettings`, `+AppointmentPrep`, `+Recovery`); `Utils/Keychain.swift`; `Utils/FileSystemManager.swift` (key handling, document/thumbnail storage, orphan cleanup); `Models/PersonalHealthInfo.swift` and `Models/HealthDocument.swift` (`AnyHealthData`) Codable shape; callers that write to the database (`HealthDataManager`, `DocumentManager`, `DocumentProcessor`, `AIChatManager`, `UnifiedContextSelectorView`, `MedicalDocumentDetailViewModel`, `SettingsView`, `DatabaseUnavailableView`, `AppStartupHealth`); git history of the `documents` create statement and the v11/v12 migrations. Scratch SQLite experiments (commands in "Reproduction" below).
- **Scope not covered**: running the real Swift migration code (builds forbidden this round; I reproduced the SQL steps in a scratch `sqlite3` database instead, which proves SQL semantics but not the Swift glue); `BloodTestResult`/`GeneticTestResult` Codable internals beyond spot checks; PHI in logs/exports/network (WS-07); actor isolation beyond SQLite connection discipline (WS-03); the import pipeline's data correctness (WS-05).
- **Verdict**: The schema-migration chain itself is sound for every upgrade history that actually exists (each step is atomic, the version row is bumped inside the same transaction, downgrade is refused without a crash) and I found no path by which a v12 or v≤11 tester silently loses rows during migration; but the layer around it is not beta-ready — a missing Keychain key silently turns every record into unreadable ciphertext with no error, several read paths swallow decode/decrypt failures and then later writes can overwrite the unread data, and PHI still sits in plaintext in places (a SQLite column, thumbnails) that the "encrypted at rest" posture implies are covered.
- **Counts**: P0=0 P1=6 P2=3 P3=6 (dropped: 0; minor observations folded into the findings above)

## Answers to the headline questions

**Can a beta tester upgrading from an existing v12 database, or migrating from an older version, lose health records?**
- **v12 → v12 (same build or later patch)**: no migration runs. No loss path in the database layer.
- **v≤11 → v12**: each version runs inside its own `db.transaction`, with `setDatabaseVersion` inside the same transaction (`DatabaseManager.swift:398-403`), so a crash or throw rolls back to the last good version and re-runs on next launch. I found no code path where the migration itself drops or corrupts rows. The v11 encryption pass reads all rows first, then updates, in one transaction; the v12 `DROP COLUMN` was reproduced in scratch with row counts preserved. Residual risks are not data loss during migration but **failure to migrate** (WS-02-09) which leaves the app on `DatabaseUnavailableView`, and a pre-migration backup that is never restorable (WS-02-07).
- **What *can* lose or hide records for an upgrader** is not the migration but the key and the read/write layer: WS-02-01 (new device / restore), WS-02-02 and WS-02-03 (silent decode failure followed by a write).
- **Downgrade**: verified. `performDatabaseMigration` throws `DatabaseError.incompatibleVersion` (`:411-413`) → `DatabaseManager.shared` converts it to an unavailable instance (`:14-21`) → `DatabaseUnavailableView` hides the erase button for that case (`isRecoverableByErasingData == false`, `:1090-1098`). No force-unwrap or trap on that path. The user's way out is installing the newer build, which is the correct one.

**Encryption-at-rest coverage**: partial. Health blobs, chat message bodies and titles, appointment preps, document file names / notes / provider / extracted text / extracted data / sections, and the imported document files themselves are AES-GCM under one Keychain key. Not covered: `health_data.metadata` (contains `patient_name`), document **thumbnails** (plaintext JPEG/PNG), `documents.tags`, `file_path`/`thumbnail_path`, and several structural columns (see schema map). The SQLite file uses iOS default protection (`completeUntilFirstUserAuthentication`); there is no WAL, so there is no `-wal`/`-shm` leak.

## Schema map (current, v12)

"Enc" = AES-GCM (CryptoKit `AES.GCM`, 256-bit key, 12-byte nonce, `combined` form; TEXT columns hold Base64 of the combined bytes).

| Table | Column | Type | Enc? | PHI? | Notes |
|---|---|---|---|---|---|
| `health_data` | `id` | TEXT PK | no | no | UUID |
| | `type` | TEXT | no | low | `personal_info` / `blood_test` (reveals what categories exist) |
| | `encrypted_data` | BLOB | **yes** | yes | whole `PersonalHealthInfo` / `BloodTestResult` JSON |
| | `created_at`, `updated_at` | INTEGER | no | low | timestamps |
| | `metadata` | TEXT (JSON) | **no** | **yes** | `BloodTestMappingService.swift:792` writes `patient_name` here (WS-02-04); other keys are source_document_id, model name, counts |
| `documents` | `id` | TEXT PK | no | no | |
| | `file_name` | TEXT NOT NULL | **yes** (since v11) | yes | falls back to raw ciphertext string on failure |
| | `file_type` | TEXT | no | no | extension |
| | `file_path` | TEXT | no | **yes** | absolute `file://` URL ending `UUID_<original name>.ext`; documented deferral (`ponytail:` at `+Documents.swift:41-44`) |
| | `thumbnail_path` | TEXT | no | low | absolute URL |
| | `processing_status`, `imported_at`, `processed_at`, `file_size` | mixed | no | no/low | |
| | `tags` | TEXT (JSON) | **no** | possible | user-entered free text (WS-02-12) |
| | `notes` | TEXT | **yes** | yes | |
| | `extracted_data` | BLOB | **yes** | yes | `[AnyHealthData]` JSON |
| | `document_date` | INTEGER | no | low | date of the medical event |
| | `provider_name` | TEXT | **yes** | yes | |
| | `provider_type`, `document_category` | TEXT | no | low | category (e.g. `genetic_test`) reveals the kind of record |
| | `extracted_text` | TEXT | **yes** | yes | full OCR text |
| | `extracted_sections` | BLOB | **yes** | yes | |
| | `include_in_ai_context`, `context_priority`, `last_edited_at` | mixed | no | no | |
| | `raw_docling_output` | — | — | — | dropped in v12 |
| `chat_conversations` | `id`, `created_at`, `updated_at`, `is_archived` | mixed | no | no | |
| | `title` | TEXT | **yes** (since v11) | yes | AI-derived from health messages |
| | `included_health_data_types`, `included_personal_info_categories` | TEXT (JSON) | no | low | which categories the user shares with the AI |
| | `tags` | TEXT (JSON) | no | possible | |
| `chat_messages` | `content` | BLOB | **yes** | yes | |
| | `id`, `conversation_id`, `role`, `timestamp`, `is_error`, `tokens`, `processing_time` | mixed | no | no | FK `conversation_id` → `chat_conversations` `ON DELETE CASCADE` |
| | `metadata` | TEXT (JSON) | no | low | model/usage metadata; spot-checked via `AIChatManager.stringifyMetadata`, not exhaustively |
| `appointment_preps` | `encrypted_data` | BLOB | **yes** | yes | |
| | `id`, `status`, `created_at`, `updated_at` | mixed | no | no | |
| `app_settings` | `key`, `value`, timestamps | TEXT/INT | no | no | disclaimer flags, app version |
| `database_version` | `version` PK, `created_at` | INTEGER | no | no | |
| *(file)* `Documents/HealthApp/Documents/Imported/UUID_name.ext` | whole file | | **yes** | yes | per-file AES-GCM, `completeUntilFirstUserAuthentication` (`FileSystemManager.swift:105,147`) |
| *(file)* `Documents/HealthApp/Documents/Thumbnails/*_thumb.jpg` | whole file | | **no** | **yes** | WS-02-05 |
| *(Keychain)* service `com.healthapp.encryption`, account `health_data_encryption_key` | 32-byte key | | n/a | n/a | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; not synchronizable; never logged in full, never in `UserDefaults` (grep-verified); first 8 hex chars of its SHA-256 logged each launch |

Other storage facts: no WAL (journal mode is SQLite's default `DELETE`; the `wal_checkpoint` at `+MedicalDocuments.swift:50` is vestigial); the database file is **not** excluded from device backups (only the migration backup copy and log files are); the single `Connection` is serialized by SQLite.swift's internal queue and used from `DispatchQueue.global` in two statistics helpers, which is safe; `PRAGMA foreign_keys = ON` is set on both connection-open paths; no busy timeout is configured but nothing else opens the file (no app group, no extension).

## Migration path

The fresh-install path sets the version straight to 12 after `CREATE TABLE IF NOT EXISTS` (`DatabaseManager.swift:380-384`) and runs no migration. An existing database runs `createBackupBeforeMigration()` once, then versions `current+1 … 12` each in `db.transaction { performMigration; setDatabaseVersion }`.

| To version | Change | Transactional? | Idempotent if re-run? | Tested by |
|---|---|---|---|---|
| 2 | no-op (model field only) | yes | yes | none |
| 3 | `createAppSettingsTable()` | yes | yes (`IF NOT EXISTS`) | none |
| 4 | 10 × `ALTER TABLE documents ADD COLUMN` + 3 indexes | yes | **no** (duplicate-column error) — safe only because the transaction rolls back | none |
| 5, 6 | no-op (relies on `decodeIfPresent` in `PersonalHealthInfo`) | yes | yes | none |
| 7 | backfill default `document_category` / `include_in_ai_context` | yes | yes | none |
| 8 | create `appointment_preps` + index | yes | yes | none |
| 9, 10 | rewrite genetic reference URLs inside plaintext `extracted_data` JSON; runs once per migration run | yes | yes; silently skips rows that fail to decode | none |
| 11 | `ADD COLUMN included_personal_info_categories`; encrypt documents `file_name`/`notes`/`provider_name`/`extracted_text`/`extracted_data`/`raw_docling_output`/`extracted_sections`; encrypt chat titles | yes | **no** (would double-encrypt) — safe only inside the transaction | none |
| 12 | `ALTER TABLE documents DROP COLUMN raw_docling_output` | yes | **no** (`no such column` on a DB that lacks it; reproduced in scratch) | none |

Test coverage: `grep` finds no test referencing `database_version`, `currentDatabaseVersion`, `DROP COLUMN` or `incompatibleVersion`; `DatabaseTests.swift` has 4 tests (init, two JSON round-trips, a chat count) and `PreBetaRegressionTests` exercises only freshly created databases. No test opens a pre-v12 fixture.

## Routed leads (WS-00 force-unwrap sites) — disposition

None of the five is a crash or data-loss risk. The baseline note that one of them is a force-unwrapped `db!` is not accurate: there is no `db!` in the database layer.

| Site | Code | Verdict |
|---|---|---|
| `DatabaseManager.swift:978` | `string.data(using: .utf8)!` | Safe: a Swift `String` always encodes to UTF-8. |
| `DatabaseManager.swift:980` | `sealedBox.combined!` | Safe: `combined` is nil only for non-12-byte nonces; `AES.GCM.seal` without a nonce argument always generates 12 bytes. Contrast `encryptData` at `:930`, which guards it properly. |
| `DatabaseManager+Documents.swift:26` | `existingDoc != nil ? mergeDocument(new:…, existing: existingDoc!) : document` | Safe: guarded by the ternary. |
| `DatabaseManager+MedicalDocuments.swift:124` | `categoryValues.first!` | Safe: inside `!categories.isEmpty`. |
| `DatabaseManager+MedicalDocuments.swift:129` | `categories!.isEmpty` | Safe: guarded by `categories != nil`. |

Worth a lint cleanup only: `encryptDataField` (`:1010`) returns `sealedBox.combined` as an optional and would store NULL if it were ever nil, which cannot happen with the current call pattern.

## Findings

### WS-02-01 — A missing Keychain key silently mints a new key over an existing database
- **Severity**: P1 · **Confidence**: CONFIRMED (code path); trigger is documented iOS behaviour, not reproduced · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:902-921` (and the duplicate at `HealthApp/HealthApp/Utils/FileSystemManager.swift:66-70`)
- **Scenario**: A tester restores a new iPhone from an iCloud or encrypted-iTunes backup. The app container is restored, including `Application Support/HealthApp/Database/health_data.sqlite` (never excluded from backup) and `Documents/HealthApp/…`. The Keychain item is `…WhenUnlockedThisDeviceOnly`, which is not restored to a different device. On first launch `getEncryptionKey()` returns nil (`errSecItemNotFound`), the code logs "CRITICAL: Database exists but encryption key is missing!", then falls straight through and generates and stores a fresh key. The database opens fine, every `health_data` blob, chat message and document field fails AES-GCM authentication, and the app shows an empty profile with no error: `fetch` swallows the failures and returns `[]` (WS-02-02), `decryptTextField` returns nil, and `fetchConversations` throws only a generic error (WS-02-08). The comment promises the "recovery scanner" will handle it, but nothing calls the scanner on this path — `HealthDataManager.loadHealthDataInternal` only reaches it when `fetch` throws `.decryptionFailed`, which record-level failures never do. New records written afterwards use the new key, so the database becomes a permanent mix of readable and unreadable rows, and the user has no clue why their history vanished.
- **Evidence**:
  ```swift
  } else {
      // Check if database already exists - if so, warn about potential data loss
      if let databaseURL = applicationSupportDatabaseURL(),
         FileManager.default.fileExists(atPath: databaseURL.path) {
          log.database("CRITICAL: Database exists but encryption key is missing! Creating new key will make existing data unreadable!", level: .critical)
          log.database("Attempting to scan database for recoverable data...", level: .error)
          // Don't throw - let the recovery scanner handle it
      }

      log.database("Creating new encryption key (no existing key found)", level: .warning)
      let newKey = SymmetricKey(size: .bits256)
      try keychain.storeEncryptionKey(newKey)
  ```
- **Fix**: When the key is absent *and* the database file exists and holds any row, throw `DatabaseError.encryptionFailed` instead of minting a key (the existing `launchRecoverySuggestion` text for that case already describes this situation), so `DatabaseUnavailableView` explains it and offers the explicit erase. Also exclude the database file and imported documents from device backups (`isExcludedFromBackup`) so a restore does not produce an unreadable shell, and have `FileSystemManager` obtain the key through the same function rather than its own `?? { newKey }`.
- **Blast radius**: every launch; `DatabaseManager.shared`, `FileSystemManager.shared`, `init(unavailable:)` (which also calls `getOrCreateEncryptionKey`), `resetDatabase()` (reuses the key). Changing the behaviour needs a UI-test fixture with a database but no Keychain item.
- **Verification**: unit test that creates a database with an encrypted row, deletes the Keychain item (`Keychain().deleteEncryptionKey()`), constructs `DatabaseManager`, and expects a thrown `DatabaseError.encryptionFailed` and no new Keychain item. Manual: restore a simulator-app container onto a fresh simulator and confirm the recovery screen appears rather than an empty app.

### WS-02-02 — An undecodable profile is skipped silently, and the app then writes a replacement that shadows it
- **Severity**: P1 · **Confidence**: PLAUSIBLE (unverified link: a decode failure of a real stored blob; the shadowing mechanism is traced end to end) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+HealthData.swift:96-116`; `HealthApp/HealthApp/Managers/HealthDataManager.swift:218,614`; `HealthApp/HealthApp/Models/PersonalHealthInfo.swift:99-128`
- **Scenario**: `PersonalHealthInfo.init(from:)` requires `id`, `allergies`, `medications`, `personalMedicalHistory`, `familyHistory`, `createdAt`, `updatedAt`, and every nested enum (`Gender`, `BloodType`, `MedicalConditionStatus`, `Frequency`, `VitalSource`…) must decode. If a later release removes or renames an enum case or adds a required field, the stored profile blob fails to decode. `fetch` logs a warning and returns `[]` (it explicitly "Don't throw[s]"), so `fetchPersonalHealthInfo()` is nil, `loadHealthData` reports success, and the UI shows an empty profile. The next Apple Health sync at launch (`AppState.syncHealthKitOnLaunch`, throttled to every 4 hours) or any vital entry runs `personalInfo ?? PersonalHealthInfo()`, which creates a **new** record with a new UUID and saves it with `insert(or: .replace)`. `fetchPersonalHealthInfo` returns `results.first` ordered by `updated_at` descending, so the sparse new row permanently shadows the real profile (name, medications, allergies, history), which stays in the table with no UI to reach it. The same shadowing can happen without any decode failure if the launch HealthKit sync runs before the first `loadHealthData()` finished, because nothing orders them (`HealthDataManager.init` fires a detached `Task`, `AppState.init` fires another).
- **Evidence**:
  ```swift
  do {
      let decryptedData = try decryptData(encryptedData, as: type)
      results.append(decryptedData)
  } catch {
      AppLog.shared.error("Failed to decrypt health data record \(recordId) …")
      corruptedRecords += 1
      corruptedRecordIds.append(recordId)
      // Continue processing other records instead of failing entirely
  }
  …
  // Don't throw - return empty array to allow app to continue
  return []
  ```
  and `HealthDataManager.swift:218`: `var info = personalInfo ?? PersonalHealthInfo()`
- **Fix**: Make `fetchPersonalHealthInfo` distinguish "no row" from "row present but unreadable" and surface the latter (throw `.decryptionFailed`, which the existing recovery-scan branch in `loadHealthDataInternal` already expects); have `updatePersonalInfo`/`mergeHealthKitData` refuse to create a new profile until an initial load has completed successfully; keep a single profile id instead of `results.first`.
- **Blast radius**: `HealthDataManager` (profile, vitals, HealthKit merge), `AIChatManager` context building, appointment prep prefill. Same pattern for `BloodTestResult` in `fetchBloodTestResults`, where the symptom is missing tests rather than a shadowing record.
- **Verification**: test that stores a profile blob whose JSON has an unknown `gender` value, calls `fetchPersonalHealthInfo`, and expects a thrown error rather than nil; test that `updatePersonalInfo` before the first load completes does not insert a row.

### WS-02-03 — Lossy reads feed full-row writes that erase ciphertext
- **Severity**: P1 · **Confidence**: PLAUSIBLE (the write path is confirmed; the trigger needs a prior decode/decrypt failure or a stale snapshot) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:362-367,381-385,233-254`; `HealthApp/HealthApp/Views/UnifiedContextSelectorView.swift:1063-1067`
- **Scenario**: `buildMedicalDocument` turns any failure into an empty value: `decryptDataField` returns nil on failure and `try? JSONDecoder().decode([AnyHealthData].self,…) ?? []` discards the whole array if one element fails (for example a `type` raw value that no longer exists). `extractedText`, `notes`, `providerName` become nil the same way. `updateMedicalDocument` and `saveMedicalDocument` then write every column unconditionally, including `encryptDataField(extractedHealthDataJson)` of `"[]"` — the original ciphertext, which could still have been read after a fix to the decoder, is overwritten. The easiest trigger is not an edit of the content at all: the AI-context selector calls the full-row `updateMedicalDocument` merely to flip `include_in_ai_context`, on a copy of the document taken when the sheet opened (`allDocuments`). A dedicated partial update, `updateDocumentAIContextStatus`, exists and is unused here. The snapshot also means a document finished by the background processor while the sheet was open is rolled back to its pre-processing state on save (lost update). `saveDocument` has a merge guard for exactly this class of bug, but `saveMedicalDocument` and `updateMedicalDocument` do not.
- **Evidence**:
  ```swift
  // Decode extracted health data (BLOB is encrypted at rest)
  let extractedHealthData: [AnyHealthData]
  if let extractedDataBlob = decryptDataField(row[documentExtractedData]) {
      extractedHealthData = (try? JSONDecoder().decode([AnyHealthData].self, from: extractedDataBlob)) ?? []
  } else {
      extractedHealthData = []
  }
  ```
  and `UnifiedContextSelectorView.swift:1063-1067`:
  ```swift
  if document.includeInAIContext != shouldInclude {
      var updatedDoc = document
      updatedDoc.includeInAIContext = shouldInclude
      try await databaseManager.updateMedicalDocument(updatedDoc)
  }
  ```
- **Fix**: Use `updateDocumentAIContextStatus` (or `updateDocumentsAIContextStatus`) in the selector; make `buildMedicalDocument` record which fields failed to decode (e.g. a `readFailures` set) and have the full-row writers keep the stored column when the corresponding field was unreadable; route `updateMedicalDocument` through the merge logic or give it a column-level partial update.
- **Blast radius**: `MedicalDocumentDetailViewModel` (notes/category edits), `DocumentProcessor` (`:227`, `:470`, `:522`), genetic review save, `UnifiedContextSelectorView`; all go through these two methods.
- **Verification**: test that corrupts one `extracted_data` element's `type`, loads the document, toggles AI context through the selector's code path, and asserts the stored `extracted_data` bytes are unchanged.

### WS-02-04 — Patient name is stored in plaintext in `health_data.metadata`
- **Severity**: P1 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Services/BloodTestMappingService.swift:791-793`; `HealthApp/HealthApp/Database/DatabaseManager+HealthData.swift:48-57`
- **Scenario**: A tester imports a lab report. The mapping service copies the patient name extracted from the report into `BloodTestResult.metadata["patient_name"]`. `save()` writes `data.metadata` JSON-serialized into the plaintext `metadata` TEXT column, in addition to the encrypted blob. Anyone with the file (device backup, forensic image of an unlocked-once device) reads the patient's full name next to the `blood_test` row, which defeats the encryption of the blob for the single most identifying field. This is the same class as prior P1-12, in a column that review did not cover.
- **Evidence**:
  ```swift
  var metadata: [String: String] = [:]
  metadata["mapping_confidence"] = String(format: "%.2f", calculateOverallConfidence(mappedParameters))
  metadata["ai_model"] = model
  metadata["extracted_count"] = String(mappedParameters.count)
  if let patientName = patientName {
      metadata["patient_name"] = patientName
  }
  ```
  `DatabaseManager+HealthData.swift:48-49`: `let metadataJson = try data.metadata.map { try JSONSerialization.data(withJSONObject: $0) }` → column `healthDataMetadata <- metadataString`
- **Fix**: Stop writing `metadata` to a plaintext column (it is already inside the encrypted blob); if the column is needed for queries, store only a whitelist (`source_document_id`, counts). Add a migration step (v13) that nulls the column, or rewrites it with the whitelist, for existing rows.
- **Blast radius**: `save`/`update` for all `HealthDataProtocol` types; `HealthDataManager` reads `source_document_id` from the decoded model, not from the column, so removal is safe. Needs a schema version bump only for the cleanup pass.
- **Verification**: test that saves a `BloodTestResult` with `metadata["patient_name"]="Jane Doe"` and asserts the raw `metadata` column does not contain `Jane`.

### WS-02-05 — Document thumbnails are plaintext PHI on disk and in device backups
- **Severity**: P1 (escalate to P0 if triage reads the rubric's "plaintext PHI" literally) · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `HealthApp/HealthApp/Utils/FileSystemManager.swift:244,272,294,312`; callers `HealthApp/HealthApp/Utils/DocumentImporter.swift:143,225,298`
- **Scenario**: Every import generates a 200×200 rendering of the first page (PDF) or the whole image and writes it with a bare `Data.write(to:)` into `Documents/HealthApp/Documents/Thumbnails/`, while the original is carefully AES-GCM encrypted. Thumbnails of photos, scans and X-rays are PHI; a lab-report first page usually exposes the lab, patient header and date. `Documents/` is included in iCloud and iTunes backups (there is no `isExcludedFromBackup` on it), so these images leave the device in plaintext to the user's backup. They are also not removed by `resetDatabase()` (WS-02-06) and not covered by the `completeUntilFirstUserAuthentication` attribute that the document files get.
- **Evidence**:
  ```swift
  guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
      throw FileSystemError.thumbnailGenerationFailed
  }
  try thumbnailData.write(to: thumbnailURL)
  return thumbnailURL
  ```
- **Fix**: Encrypt thumbnails with the same `encryptData` helper and decrypt on display, or render them on demand from the encrypted original and keep only an in-memory cache; at minimum set `isExcludedFromBackup` on the thumbnails directory and apply a protection class. Add a one-time cleanup that deletes existing plaintext thumbnails.
- **Blast radius**: `DocumentGridView`/`DocumentListView` thumbnail rendering, `DocumentManager.regenerateThumbnail`, `StorageUsageView.cleanupOldThumbnails`, the persisted `thumbnail_path` column.
- **Verification**: import a PDF in a test harness with a temp base directory and assert no file under `Thumbnails/` starts with the JPEG magic `FF D8 FF`.

### WS-02-06 — "Reset Database" promises a backup and a full wipe and does neither
- **Severity**: P1 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Views/SettingsView.swift:50,1014-1016`; `HealthApp/HealthApp/Database/DatabaseManager.swift:745-783`
- **Scenario**: A tester taps Reset Database. The confirmation says "permanently delete ALL your health data, documents, and chat history … A backup will be created first." `resetDatabase()` creates no backup — it deletes the migration backups (`deleteMigrationBackups()`), then the database file. It also does not touch `Documents/HealthApp/Documents/Imported/*` (encrypted originals with `UUID_<original name>` file names), the plaintext thumbnails, or the Keychain key, yet the success message says "All health data has been permanently deleted." The tester who believed a backup existed has no way to restore; a privacy-conscious tester who resets before returning a device still has their documents' file names and thumbnails on disk. (The same statements on `DatabaseUnavailableView` are accurate about the backup: it says there is none.)
- **Evidence**:
  ```swift
  case .database: return "⚠️ WARNING: This will permanently delete ALL your health data, documents, and chat history. This action cannot be undone. A backup will be created first."
  ```
  ```swift
  // Migration backups hold pre-encryption plaintext PHI — a database
  // reset must erase them too, or "permanently deleted" is a lie.
  deleteMigrationBackups()
  ```
- **Fix**: Remove the backup sentence (or implement an export-then-reset flow), and have the reset path also delete the `Documents/Imported` and `Thumbnails` directories (and clear the in-memory managers' state). Update the success message to match what was deleted.
- **Blast radius**: `SettingsView`, `DatabaseUnavailableView.eraseAndRebuild`, `FileSystemManager`, `DocumentManager`/`HealthDataManager` in-memory state after reset.
- **Verification**: test that imports a document, calls the full reset, and asserts `Imported/` and `Thumbnails/` are empty; UI test asserting the confirmation text does not mention a backup.

### WS-02-07 — The pre-migration backup is unbounded on failure, never restorable, and can be destroyed by the erase button
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: M
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:390,435-444,449-456`; `HealthApp/HealthApp/Views/DatabaseUnavailableView.swift:90`
- **Scenario**: (a) A migration step throws (for example a disk-full error during the v11 encryption pass). The transaction rolls back, the app lands on `DatabaseUnavailableView`, and the backup stays. On the next launch `createBackupBeforeMigration()` runs again and writes another full-size, timestamped copy (`health_data.sqlite.backup.<time>`); a tester who relaunches five times with a 300 MB database has used 1.5 GB more of a disk that was probably already full. Nothing prunes them except a later successful migration or Reset. (b) `grep` finds no code that reads a `*.backup.*` file; there is no restore path, and the container is not user-visible, so the "copy taken before the upgrade started" the recovery text points to cannot be used by the tester. (c) For databases older than v11 the copy holds plaintext document text, protected only by the default file-protection class. (d) The Erase button's alert says "there is no backup to restore from"; erasing then silently deletes the only copy. (e) The whole migration, including a loop that loads every document row (with full `extracted_text`) into memory, runs synchronously on the main thread during `DatabaseManager.shared` initialisation; a large database can exceed the launch watchdog, producing a kill-and-retry loop that creates a new backup each time.
- **Evidence**:
  ```swift
  private func createBackupBeforeMigration() throws {
      var backupURL = databaseURL.appendingPathExtension("backup.\(Date().timeIntervalSince1970)")
      try FileManager.default.copyItem(at: databaseURL, to: backupURL)
  ```
- **Fix**: Reuse a single well-known backup path (skip if a valid one already exists for this source version), delete older ones, and either add a "restore pre-upgrade copy" action to `DatabaseUnavailableView` or stop advertising the copy. Move migration off the launch path (show progress, run on a background queue).
- **Blast radius**: `DatabaseManager.init`, `resetDatabase`, `DatabaseError.launchRecoverySuggestion` copy, `DatabaseUnavailableView`.
- **Verification**: test that forces a migration failure (inject a throwing step) three times and asserts at most one backup file remains.

### WS-02-08 — One undecryptable chat message hides the entire conversation list
- **Severity**: P2 · **Confidence**: CONFIRMED · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:49-71,379-383`; `HealthApp/HealthApp/Managers/AIChatManager.swift:180-189`
- **Scenario**: `fetchConversations` builds every conversation, which fetches and decrypts every message. `buildChatMessage` uses `try decryptString`, so a single corrupt or foreign-key message row throws, the catch block replaces the error with `.decryptionFailed`, and the whole call fails. `AIChatManager.loadConversations` then leaves `conversations` empty and shows "Failed to load conversations"; the tester's whole chat history is invisible until the bad row is removed, and there is no tool to find or delete it. `fetchAppointmentPreps` already handles this correctly by skipping the bad row; `fetch` for health data does too.
- **Evidence**:
  ```swift
  let iterator = try db.prepareRowIterator(query)
  while let row = try iterator.failableNext() {
      let conversation = try await buildChatConversation(from: row)
      results.append(conversation)
  }
  } catch { … throw DatabaseError.decryptionFailed }
  ```
- **Fix**: Catch per conversation (and per message) and substitute a placeholder message such as "[message could not be read]" instead of failing the list; log the ids.
- **Blast radius**: `fetchConversations`, `fetchArchivedConversations`, `fetchConversation`, `searchConversations`.
- **Verification**: test that overwrites one `chat_messages.content` with random bytes and asserts the other conversations still load.

### WS-02-09 — Migrations are untested and brittle against any schema that does not match history
- **Severity**: P2 · **Confidence**: CONFIRMED (properties reproduced in scratch SQLite) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:380-384,417-425,474-483,576`
- **Scenario**: The chain is correct only for databases whose history matches the code. Three weak spots: (1) The v4 and v12 steps are unconditional `ADD COLUMN`/`DROP COLUMN`; `DROP COLUMN` on a database that does not have the column fails with `no such column` (reproduced), the transaction rolls back, and every later launch fails identically, landing the tester on `DatabaseUnavailableView` with an erase button. The git history shows the v11-era `create` statement did include the column, so ordinary upgraders are fine; a database created by any intermediate or UI-test build is not. (2) `getCurrentDatabaseVersion` catches every error and returns 0, and version 0 means "fresh database, set v12, skip all migrations" without checking whether the data tables already contain rows. A transient read error on the version table, or an old database with an empty `database_version` table, is silently stamped v12 with an old schema and unencrypted PHI. (3) No test opens a pre-v12 database: the only automated evidence for the chain is that fresh databases open.
- **Evidence**:
  ```swift
  } catch {
      // Table doesn't exist or is empty, assume version 0
      return 0
  }
  ```
  ```swift
  case 12:
      try db.run("ALTER TABLE documents DROP COLUMN raw_docling_output")
  ```
- **Fix**: Make column steps conditional (`pragma_table_info` check), treat "version 0 but `health_data`/`documents` has rows" as an error or as v1, narrow the `catch` to "no such table", and add fixture tests for v3, v10, v11 databases.
- **Blast radius**: `DatabaseManager.init` and `createTables()` (reset path); no runtime effect on healthy databases.
- **Verification**: tests that build v3, v10 and v11 fixtures (with the old `create` statements from git history), run `DatabaseManager(databaseURL:)`, and assert row counts, decryptability, and the final column set.

### WS-02-10 — Absolute file URLs are persisted in `file_path` / `thumbnail_path`
- **Severity**: P3 · **Confidence**: PLAUSIBLE (unverified link: how often the app container path changes in practice; restore and reinstall do change it) · **Effort**: M
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:45-46`; consumers `HealthApp/HealthApp/Managers/DocumentManager.swift:380`, `HealthApp/HealthApp/Utils/DocumentExporter.swift:215`
- **Scenario**: Paths are saved as `file:///var/mobile/Containers/Data/Application/<UUID>/Documents/HealthApp/…`. If the container UUID changes, `DocumentProcessor.resolveDocumentFilePath` and the detail view repair the path lazily, but the delete path does not: `DocumentManager.deleteDocument` deletes the row, sees `fileExists == false`, skips the file, and reports success, leaving an encrypted original plus its plaintext thumbnail on disk indefinitely. Export reads `document.filePath` directly and fails.
- **Evidence**:
  ```swift
  documentFilePath <- mergedDoc.filePath.absoluteString,
  documentThumbnailPath <- mergedDoc.thumbnailPath?.absoluteString,
  ```
- **Fix**: Store only the file name (or a path relative to the documents directory) and resolve it at read time through `FileSystemManager`.
- **Blast radius**: every consumer of `MedicalDocument.filePath`; needs a migration step that rewrites existing rows.
- **Verification**: test that changes the base directory after saving a document and asserts open, export and delete still reach the file.

### WS-02-11 — A transient Keychain failure at launch is latched for the life of the process
- **Severity**: P3 · **Confidence**: PLAUSIBLE (unverified link: the app currently declares no background modes, so a locked-device launch is unlikely today) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:14-21`; `HealthApp/HealthApp/HealthAppApp.swift:247`; `HealthApp/HealthApp/Utils/Keychain.swift:75-80`
- **Scenario**: The key is `WhenUnlockedThisDeviceOnly`. If the process starts while the device is locked, `SecItemCopyMatching` returns `errSecInteractionNotAllowed`; `getEncryptionKey()` correctly throws (it does not regenerate), but `DatabaseManager.shared` is a `static let` closure, so the failure is cached forever and `DatabaseUnavailableView` appears even after unlock until the process is killed. `SettingsManager` already documents and handles the same race for the API key (`reloadAPIKeyIfUnreadable`); the database does not. If the unavailable instance's second key read happens to succeed after unlock, `canResetDatabase` becomes true and the erase button is offered for what was only a transient lock.
- **Fix**: Retry initialisation when the error is a `KeychainError.retrieveFailed(errSecInteractionNotAllowed)` once protected data becomes available, and hide the erase button for that error. Alternatively relax the item to `AfterFirstUnlockThisDeviceOnly`, as `AWSCredentialsHelper` already does.
- **Blast radius**: key accessibility affects `FileSystemManager` too; changing the class requires rewriting the existing item (`SecItemUpdate`, which `Keychain.write` already supports).
- **Verification**: inject a failing `KeychainStoring` and assert that re-initialisation succeeds after the stub starts returning the key.

### WS-02-12 — Other plaintext columns carry free-text and category metadata
- **Severity**: P3 · **Confidence**: CONFIRMED (columns), PLAUSIBLE (what users type) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:29-30,51`; `+Chat.swift:15-16,29`; schema map above
- **Scenario**: `documents.tags` and `chat_conversations.tags` are user-editable free text stored as JSON in plaintext ("diabetes", a doctor's name). `document_category`, `document_date`, `provider_type`, `included_health_data_types` and `included_personal_info_categories` reveal what kinds of records exist and when. `file_path` carries the original file name (documented as deferred, so not counted here). Individually low impact, but they reintroduce, in weaker form, the leak that v11 closed for file names.
- **Fix**: Encrypt `tags` with the existing `encryptTextField` helper in a v13 pass; accept the structural columns as search/filter metadata and say so in the privacy documentation.
- **Blast radius**: `DocumentManager` tag search (already in memory), tests that read tags.
- **Verification**: test asserting the raw `tags` column differs from the plaintext tag.

### WS-02-13 — `saveConversation` uses `INSERT OR REPLACE` on a cascading parent
- **Severity**: P3 · **Confidence**: CONFIRMED (SQLite behaviour reproduced); no current caller is affected · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:21-37`
- **Scenario**: `chat_messages.conversation_id` has `ON DELETE CASCADE` and `PRAGMA foreign_keys = ON`. Replacing an existing `chat_conversations` row deletes it first, which cascades and deletes all of its messages; the method then re-inserts only the messages held in `conversation.messages`, without a transaction. I reproduced the cascade with `sqlite3` 3.54 (message count 2 → 0 after `INSERT OR REPLACE` of the parent). Today only `AIChatManager.startNewConversation` calls it, with a brand-new empty conversation, so nothing is lost; any future caller that re-saves a stale in-memory conversation (or an app kill between the replace and the re-insert loop) deletes history. `updateConversation` (a column `UPDATE`) is the safe API and is what every other caller uses.
- **Evidence**:
  ```swift
  let insert = chatConversationsTable.insert(or: .replace, conversationId <- conversation.id.uuidString, …)
  try db.run(insert)
  // Save all messages
  for message in conversation.messages { try await saveMessage(message, conversationId: conversation.id) }
  ```
- **Fix**: Use an upsert (`INSERT … ON CONFLICT(id) DO UPDATE`) and wrap the conversation plus message inserts in `db.transaction`.
- **Blast radius**: only `saveConversation` and its tests.
- **Verification**: test that saves a conversation with two messages, saves it again with an empty `messages` array, and asserts both messages remain.

### WS-02-14 — Fresh-install schema differs from the migrated schema; the reset path differs again
- **Severity**: P3 · **Confidence**: CONFIRMED (reproduced in scratch) · **Effort**: S
- **Location**: `HealthApp/HealthApp/Database/DatabaseManager.swift:204-208` vs `:477-482`; `:872-880` vs `:260-270`
- **Scenario**: `Expression<String>`/`Expression<Bool>`/`Expression<Int>` produce `NOT NULL DEFAULT …` on fresh installs, while the v4 `ALTER … ADD COLUMN` steps create nullable columns (`document_category`, `include_in_ai_context`, `context_priority`: `notnull=0` migrated, `notnull=1` fresh). The code tolerates this (`try?` with fallbacks, v7 backfill), so I found no wrong behaviour today; the risk is that a future query or constraint behaves differently only for upgraders. Separately `createTables()` (used by `resetDatabase`) omits three indexes (`idx_documents_date`, `_category`, `_ai_context`) that `init` creates, so a reset database is slower on date and category filters than a fresh install.
- **Fix**: Make the migration add the same constraints via a table-rebuild step (not needed now), and factor the table/index creation into one function used by both `init` and `createTables`.
- **Blast radius**: `DatabaseManager` only.
- **Verification**: a test that compares `pragma_table_info` and `sqlite_master` of a fresh database and a v3-migrated fixture.

### WS-02-15 — Dead destructive helpers remain in the database and file layers
- **Severity**: P3 · **Confidence**: CONFIRMED (no callers found by grep) · **Effort**: S
- **Location**: `DatabaseManager+HealthData.swift:255-309` (`cleanupCorruptedRecords`); `HealthApp/HealthApp/Managers/DocumentManager.swift:501-513` and `Utils/FileSystemManager.swift:437-456` (`cleanupOrphanedFiles`); `Utils/Keychain.swift:89` (`deleteEncryptionKey`); `DatabaseManager.swift:36-40` (`encryptionKeyFingerprint`)
- **Scenario**: None runs today, but each is one accidental call from data loss. `cleanupOrphanedFiles` deletes every file not named in an in-memory array, so a call made while `documents` is empty (load failed, not yet loaded) would remove every imported original. `cleanupCorruptedRecords` deletes rows while iterating the same query, which the migration code itself notes is undefined, and its "is it corrupt" test is only a size check. `deleteEncryptionKey` has no caller. `Definition of Done` asks for unused code to be removed.
- **Fix**: Delete them (or add a safety check, such as refusing to run when the array is empty, if they are wanted).
- **Blast radius**: none at runtime; tests that reference them, if any.
- **Verification**: build still passes after removal.

## Structural risks (max 5 bullets)

- **One key, no versioning, no escrow**: all data and all files depend on a single Keychain item that is not backed up, with no key id stored in the ciphertext or the database; any key loss is total and silent (WS-02-01), and key rotation would be a full rewrite.
- **Error handling converts failures to empty data**: `try?`/`?? []`/`return []` in `fetch`, `buildMedicalDocument` and the Codable decoders means the read layer cannot distinguish "no data" from "data I cannot read", and write paths built on those reads can destroy the unreadable data (WS-02-02/03).
- **Strict whole-blob Codable with no schema version**: `PersonalHealthInfo`/`BloodTestResult` blobs have no embedded version and required fields, so any model change is a silent data-hiding risk; the migration numbers 2, 5, 6 are no-ops that rely on this decoder.
- **No upgrade test fixtures**: there is no pre-v12 database in the test suite, so none of the 11 migration steps has ever been verified by an automated test.
- **Database work happens on the main thread during launch** (`static let shared` initialiser, migration, v11 encryption loop), so first-launch cost scales with the user's data and is bounded only by the OS watchdog.

## Reproduction (scratch work, nothing in the repo touched)

All scratch databases live under `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/` (`ws02.sqlite`, `migrated.sqlite`, `fresh.sqlite`). `sqlite3 --version` = 3.54.0.

1. REPLACE cascade (WS-02-13) and DROP COLUMN behaviour (WS-02-09):
   ```bash
   cd "$SCRATCH"; rm -f ws02.sqlite; sqlite3 ws02.sqlite <<'SQL'
   PRAGMA foreign_keys=ON;
   CREATE TABLE chat_conversations(id TEXT PRIMARY KEY NOT NULL, title TEXT);
   CREATE TABLE chat_messages(id TEXT PRIMARY KEY NOT NULL, conversation_id TEXT NOT NULL, content BLOB,
     FOREIGN KEY(conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE);
   INSERT INTO chat_conversations VALUES('c1','t');
   INSERT INTO chat_messages VALUES('m1','c1','x'),('m2','c1','y');
   INSERT OR REPLACE INTO chat_conversations VALUES('c1','t2');
   SELECT count(*) FROM chat_messages;            -- prints 0
   CREATE TABLE documents(id TEXT PRIMARY KEY, a TEXT, raw_docling_output BLOB);
   BEGIN; ALTER TABLE documents DROP COLUMN raw_docling_output; COMMIT;   -- ok
   BEGIN; ALTER TABLE documents DROP COLUMN raw_docling_output; COMMIT;   -- "no such column"
   SQL
   ```
2. Migrated vs fresh column set (WS-02-14): `migrated.sqlite` was built from a v3-era `documents`/`chat_conversations` schema with one row each, then the v4 `ALTER`s, v11 `ADD COLUMN` and v12 `DROP COLUMN` were applied verbatim from `DatabaseManager.swift:474-483,569,576` in the same transaction pattern; both rows survived (`rows kept|1|1`). `fresh.sqlite` was created from the current `create` statement as SQLite.swift would emit it (hand-written DDL, so `BOOLEAN` vs `INTEGER` spelling may differ from the generated text). Comparison: `sqlite3 X.sqlite "select name,type,\"notnull\",dflt_value from pragma_table_info('documents') where name in ('document_category','include_in_ai_context','context_priority')"` → migrated `notnull=0`, fresh `notnull=1`.
3. Not reproduced: the Swift encryption pass of v11 (cannot run without building), and the iCloud-restore key loss of WS-02-01 (needs two devices).

## Machine-readable summary
```json
[
  {"id":"WS-02-01","title":"Missing Keychain key silently mints a new key over an existing database","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:902","HealthApp/HealthApp/Utils/FileSystemManager.swift:66"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-02","title":"Undecodable profile skipped silently; replacement record shadows it","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Database/DatabaseManager+HealthData.swift:96","HealthApp/HealthApp/Managers/HealthDataManager.swift:218","HealthApp/HealthApp/Managers/HealthDataManager.swift:614"],"effort":"M","area":"data-integrity"},
  {"id":"WS-02-03","title":"Lossy document reads feed full-row writes that erase ciphertext","severity":"P1","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:362","HealthApp/HealthApp/Database/DatabaseManager+MedicalDocuments.swift:233","HealthApp/HealthApp/Views/UnifiedContextSelectorView.swift:1067"],"effort":"M","area":"data-integrity"},
  {"id":"WS-02-04","title":"Patient name stored in plaintext health_data.metadata column","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/BloodTestMappingService.swift:792","HealthApp/HealthApp/Database/DatabaseManager+HealthData.swift:48"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-05","title":"Document thumbnails are plaintext PHI on disk and in device backups","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/FileSystemManager.swift:244","HealthApp/HealthApp/Utils/DocumentImporter.swift:143"],"effort":"M","area":"data-integrity"},
  {"id":"WS-02-06","title":"Reset Database promises a backup and full wipe but creates no backup and leaves files","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Views/SettingsView.swift:50","HealthApp/HealthApp/Database/DatabaseManager.swift:745"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-07","title":"Pre-migration backup is unbounded on failure, unrestorable, and erasable","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:435","HealthApp/HealthApp/Views/DatabaseUnavailableView.swift:90"],"effort":"M","area":"data-integrity"},
  {"id":"WS-02-08","title":"One undecryptable chat message hides the whole conversation list","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:60","HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:382"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-09","title":"Migrations untested and brittle against schemas that differ from history","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:380","HealthApp/HealthApp/Database/DatabaseManager.swift:417","HealthApp/HealthApp/Database/DatabaseManager.swift:576"],"effort":"M","area":"data-integrity"},
  {"id":"WS-02-10","title":"Absolute file URLs persisted in file_path and thumbnail_path","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:45","HealthApp/HealthApp/Managers/DocumentManager.swift:380"],"effort":"M","area":"data-integrity"},
  {"id":"WS-02-11","title":"Transient Keychain failure latched for process lifetime","severity":"P3","confidence":"PLAUSIBLE","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:14","HealthApp/HealthApp/Utils/Keychain.swift:75"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-12","title":"Plaintext tags and category metadata columns","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager+Documents.swift:51","HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:29"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-13","title":"saveConversation INSERT OR REPLACE cascades message deletion","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager+Chat.swift:21"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-14","title":"Fresh-install and migrated schemas differ; reset path omits indexes","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager.swift:204","HealthApp/HealthApp/Database/DatabaseManager.swift:477","HealthApp/HealthApp/Database/DatabaseManager.swift:872"],"effort":"S","area":"data-integrity"},
  {"id":"WS-02-15","title":"Dead destructive helpers remain (orphan cleanup, corrupted-record cleanup, key delete)","severity":"P3","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Database/DatabaseManager+HealthData.swift:255","HealthApp/HealthApp/Utils/FileSystemManager.swift:437","HealthApp/HealthApp/Managers/DocumentManager.swift:501"],"effort":"S","area":"data-integrity"}
]
```
