# V13 restore verification

Device: iPad Pro 11-inch (M5), iOS 26.5, F8530E9D. Build of the working tree at HEAD (05c1d940), launched with `--ui-testing --disable-healthkit-sync --skip-disclaimer` on every launch, so every result is from the **UI-testing store** (`<container>/tmp/BisonHealthAIRegressionUITests/Database/health_data.sqlite`). Extraction used a local mock OpenAI-compatible server (`/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/mock2.py`) returning 5 values; the app's reconciler produced 10 review rows (2 auto-accepted, 7 needing a choice).

| # | Check | Verdict |
|---|-------|---------|
| 1a | Row written when the review sheet appears | CONFIRMED |
| 1b | Force-quit then relaunch brings the sheet back | CONFIRMED, with a caveat (see below) |
| 1c | Cancel dismisses sheet but keeps the row; sheet returns next launch | CONFIRMED (same caveat) |
| 1d | Completing the import deletes the row | CONFIRMED |
| 2 | v12 database migrates to v13 on launch, data intact | CONFIRMED |

## Check 1 evidence
- Review sheet ("Review Lab Results", button "Import 3 of 10") shown after Process Now: `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c1-sheet.png`.
- `select document_id,length(payload),created_at from pending_import_reviews` -> `E9CAAD8C-B143-483C-B4A8-769840FEE9C4|11824|1792795274` (1 row; schema: document_id TEXT PK, payload TEXT, created_at INTEGER).
- `simctl terminate` + relaunch: row count still 1. App log: `Restoring 1 un-reviewed lab import(s) from a previous session`. Sheet visible (identical, "Import 3 of 10") after opening the Documents tab: `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c1-after-forcequit-docs.png`. Immediately after relaunch (Records tab) no sheet was shown: `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c1-after-forcequit.png`.
- Cancel tapped: row count 1 afterwards. Terminate/relaunch/Documents tab: sheet back again: `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c1-relaunch-after-cancel.png`.
- Selected a value and tapped Import ("Import 4 of 10"): row count 0, health_data 1 row, Records shows a Oct 23 2026 lab entry (4 tests, Total Cholesterol 205 mg/dL): `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c2-records-after-migration.png`.

## Check 2 evidence
Data before: 4 documents, 1 health_data row. Terminated app, then `DROP TABLE pending_import_reviews; DELETE FROM database_version; INSERT INTO database_version (version, created_at) VALUES (12, 0);`. Relaunched.
- App log (`Documents/HealthApp/Logs/app-2026-10-23.log`; copy of lines in `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/migration-log-lines.txt`):
  `[DatabaseManager.swift:408] Migration needed from v12 to v13` and `[DatabaseManager.swift:608]    ✓ Created pending_import_reviews table`
- No crash. `database_version` now `12|0` and `13|1792795668`; `max(version)` = 13. `pending_import_reviews` exists again. 4 documents and 1 health_data row unchanged; all four documents and the cholesterol lab entry are visible in the UI (`/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c2-docs-after-migration.png`, `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/v13/c2-records-after-migration.png`).

## Unexpected / worth a look
1. **Restore is tied to the Documents tab.** `restorePendingImportReviews()` is called from a `.task` in `DocumentsView` (ContentView.swift ~731), and the sheet is attached to the same view. After relaunch the app lands on Records and no sheet appears until the user opens Documents. Stored review is not lost, but "the review returns on launch" is only true once that tab is shown. If it should surface anywhere, move the restore call to app/root level.
2. **First Import tap did nothing.** With the sheet at "Import 3 of 10" (no choices made), tapping Import left the sheet up and wrote nothing (health_data 0, row still 1). After selecting a value ("Import 4 of 10") Import worked. Not clear if the button was disabled or the tap was swallowed; I did not investigate further.
3. "Accept All Recommended" appeared dimmed because nothing was starred Recommended (expected per the brief).
4. `database_version` accumulates a row per version (12 and 13 both present); readers must use MAX(version).
