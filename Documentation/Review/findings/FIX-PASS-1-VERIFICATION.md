# Fix pass 1 - runtime verification

Run on iPad Pro 11-inch (M5) simulator (F8530E9D), debug build of the working tree at HEAD (866e246d plus the parser commit "never auto-accept a lab value whose unit or range came from the registry"). Launch args `--ui-testing --disable-healthkit-sync --skip-disclaimer`; all results are from the ui-testing store. Log captured with `simctl spawn ... log stream`; key lines are in the scratchpad `fp1/key-log-lines.txt`. Screenshots are in `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/fp1/`.

| # | Check | Verdict |
|---|-------|---------|
| 1 | Import stops retrying after 3 attempts (WS-09-01) | CONFIRMED FIXED (live UI does not show the failure; see unexpected findings) |
| 2 | No fabricated lab record (WS-05-04) | CONFIRMED FIXED |
| 3 | Document failures visible (WS-08-01/04) | PARTIALLY FIXED - alert appears for DocumentManager errors; import-time and processing failures still show nothing |
| 4 | Missing unit/range goes to review (parser fix) | CONFIRMED FIXED (deterministic parser path; LLM-candidate path not exercised) |

## 1. Retry cap
Setup: fresh install, simulator keychain reset (see note below), Extraction Provider left at its default (On-Device AI, "No vision-capable on-device model is downloaded"). Imported `lab-report.pdf` (text PDF), tapped Process Now.

Log, `DocumentProcessor`:
- 13:21:35 `Processing document (attempt 1/3)` -> `Processing failed ... No on-device vision model is downloaded` -> `Retrying in 2.0 seconds (attempt 2/3)`
- 13:21:40 `attempt 2/3` -> failed -> `Retrying in 4.0 seconds (attempt 3/3)`
- 13:21:47 `attempt 3/3` -> failed -> `Maximum retry attempts reached, marking as failed` -> `Status updated to failed` (13:21:50)

Nothing further logged in the following ~65 s (3 "Processing document" lines in total, versus 13+ in 50 s before). A second run at 13:23:18 (after tapping Skip on the type sheet, which re-queues the document) again ran exactly 1/3, 2/3, 3/3 and stopped. An unrelated corrupt document (jpeg bytes named .pdf) also went 1/3, 2/3, 3/3 then failed; re-queueing it started at `attempt 3/3` and failed immediately, showing the count is carried across re-queue.
The list row shows "Failed" (red) once the list reloads (check1-failed-state-after-refresh.png, and lab-report.pdf in check2/s41).

## 2. No fabricated lab record
Extraction Provider set to OpenAI-compatible against the local mock (`mock.py`, returns `{}`). Imported `nolab-report.pdf`, a lab-report-shaped PDF (header, column titles, "no analytes reported") with no values. Processed once as "other" and again as Lab Report.
Log: `LabReportParser: 0 candidates`, `LLM pass found 0 candidates`, `No candidates from any pass, falling back to item-based mapping`, `Lab report yielded no parseable values - importing no health data rather than a placeholder`. Document ended Completed, text saved. Health > Records > Lab Results still reads "No lab results" (check2-records-empty.png). No "Lab Report Processed" row anywhere.

## 3. Failures visible
- Regenerate Thumbnail on the corrupt `jpeg-named.pdf` (DocumentDetailView -> `DocumentManager.regenerateThumbnail` -> `lastError`) produced an alert "Documents / Failed to generate thumbnail" with a Dismiss button. Log: `ErrorHandler.swift:128 [Documents] Failed to generate thumbnail`. (check3-alert-thumbnail.png). That is the new `lastError -> ErrorHandler` path working.
- Importing a 0-byte `zero.pdf` via the file picker: log `Failed to import document: The selected file is empty.` and NO alert (check3-zero-byte-no-alert.png). Cause: `DocumentImporter.importMultipleDocuments` catches each per-file error and only writes `DocumentImporter.lastError`, which nothing reads, so `DocumentManager.importDocuments` never sees a throw. The commit message lists this as not addressed. Same for an unsupported type, which goes through the same path (not separately run).
- Processing failures (check 1) also raise no alert.

## 4. Unit / range rule
Imported `mixed-units.pdf`: Sodium 140 mmol/L 135-145; Chloride 101 mmol/L 98-107; Potassium 4.1 mmol/L (no range); Glucose 85 (no unit, no range); Creatinine 0.9 mg/dL (no range).
Log: `Reconciler: 10 candidates -> 2 auto-accepted, 3 need review`; `3 groups need review (2 auto-accepted) - showing review sheet`; `Blood test has pending review - skipping save until user reviews`. The "Review Lab Results" sheet appeared (no silent "Imported N" toast). Auto-imported group = exactly Sodium and Chloride (both with unit and range). Review rows = Creatinine, Glucose, Potassium. Glucose shows "85 mg/dL, Expected 70-100": the unit and range there are the registry substitutes, source snippet "Glucose 85" (check4-review-sheet-*.png). I cancelled the sheet, so nothing was saved.
Not tested: the LLM-candidate path with a unit-less value from the mock (mock only returns `{}`), and the `BloodTestMappingService` change (isAbnormal no longer uses the registry range) beyond what the review sheet displays.

## Unexpected / worth fixing
1. Live UI does not reflect the failed state. After the 3 failed attempts the Documents list and the open detail sheet kept showing "Pending" (with Process Now) until the tab was switched, and no message appears. A user watching sees the same silent "Pending" as before, just not forever. A refresh shows "Failed".
2. Import-time errors (empty or unsupported file) still silent; see check 3.
3. Review sheet pre-selects ("Recommended" star) values whose unit and range were substituted, and displays the registry unit as if the lab stated it (Glucose "85 mg/dL"). The source snippet is shown, but the unit label is not marked as assumed.
4. Pre-existing quirk, not a regression: the OCR layout pass produces duplicate candidates, e.g. Creatinine "0.9 ng/dL" and "0.9 mg/dL", forcing a "Multiple values found" review. Also the full sample `lab-report.pdf` gives only 2 auto-accepted of 18 candidates.
5. The Document Type sheet re-appears after dismissing the detail sheet, and Skip/Done re-triggers processing (a fresh 1/3 cycle for the same document). Not caused by these fixes.
6. Environment note: the previous run's OpenAI-compatible provider settings survived an uninstall (modelPreferences backup in the simulator keychain). I ran `xcrun simctl keychain F8530E9D... reset` on this iPad simulator only, to get the true fresh-install default for check 1. No source or git changes were made.
