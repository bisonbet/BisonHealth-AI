# WS-05 — Document import & extraction pipeline

- **Agent / model**: Claude Sonnet 5.5 (`claude-sonnet-5-5`), read-only review, no build, no simulator
- **Date**: 2026-10-22
- **Commit reviewed**: `b94c39f6` (branch `main`)
- **Scope actually covered**: `Services/LabReportParser.swift` (all, incl. `LabCandidateReconciler`, `CloudVisionLabExtraction`), `Utils/BloodTestValueValidator.swift` (all), `Models/BloodTestResult.swift` (model, parameter registry head, `LabMeasurementContext`, `matchLabParameter`), `Models/DuplicateBloodTestCandidate.swift`, `Services/BloodTestMappingService.swift` (all), `Services/MedicalDocumentExtractor.swift` (date + AI-parse paths), `Services/NativeDocumentExtractor.swift` (all), `Services/DocumentProcessor.swift` (queue, status machine, `extractHealthData`, lab pipeline, placeholder/fallback builders, helpers, persistence), `Managers/DocumentManager.swift` (import, delete, process, orphan helper), `Utils/DocumentImporter.swift`, `Utils/FileSystemManager.swift` (store/retrieve/delete/thumbnail/cleanup), `Utils/DocumentExporter.swift` (PDF report), `Managers/HealthDataManager.swift` (`addBloodTest`, duplicate guard, `linkExtractedDataToDocument`), `Views/BloodTestImportReviewView.swift`, review/banner/share wiring in `ContentView.swift` and `Views/DocumentDetailView.swift`, `Views/BatchProcessingView.swift` (actions only).
- **Scope not covered**: `DocumentCameraView`, `DocumentGridView`, `DocumentListView`, `MedicalDocumentDetailView` (only grepped for status/lastError use); `GeneticTestParser`; the remaining ~420 registry entries of `standardizedLabParameters` and the alias table (spot-checked via a matcher harness, not audited line by line); the SQL layer beyond `updateDocumentStatus` / `updateDocumentExtractedData` / `saveDocument`. **Nothing was run in the app.** Every UI-timing or device-memory conclusion is marked code-trace.
- **How the parsing findings were verified**: the real `LabReportParser`, `LabCandidateReconciler`, `BloodTestValueValidator`, `BloodTestResult.matchLabParameter` and `BloodTestImportGroup` sources were compiled unmodified with `swiftc` against a ~15-line stub (`AppLog`, `NativeDocumentExtractor.PageText`, `HealthDataProtocol`) and fed text rows. Those outputs are quoted below as "harness". Harness sources: `/private/tmp/claude-501/-Users-champ-Sources-BisonHealth-AI/ec9f60b8-3980-494c-a902-1c729c95dae3/scratchpad/h/` (rebuild: `swiftc -O -swift-version 5 stub.swift main.swift <app>/Models/BloodTestResult.swift <app>/Utils/BloodTestValueValidator.swift <app>/Services/LabReportParser.swift <app>/Models/DuplicateBloodTestCandidate.swift`). PDFKit / Vision / DateFormatter behaviours were checked with small macOS scripts in `.../scratchpad/inputs/`. The wiring from parser output to the stored record is code-trace.
- **Verdict**: Not beta-ready for lab-value import. The structural pipeline (status machine, queue, share/export, delete-while-processing guards) is in good shape after the prior review, but the parser can produce wrong-but-confident values (wrong unit, wrong section, wrong reference range) that are imported with no user confirmation, one heuristic silently discards whole reports, and every import rejection is invisible to the user.
- **Counts**: P0=0 P1=6 P2=9 P3=0 (dropped: 8 — recorded only as rows in the robustness table)

## Direct answers to the coordinator's four questions

1. **Can a lab value be parsed wrongly and shown as fact?** Yes, five distinct ways, all reproduced against the real parser code: a missing unit is replaced by the registry default unit (WS-05-01); a urine-section state leak files serum values as urine analytes (WS-05-02); a date in a neighbouring cell becomes the reference range (WS-05-07); decimal-comma reports are read as 10x values with garbled ranges (WS-05-09); a placeholder "Lab Report Processed — Document imported successfully" row is saved as a real blood test summarised "1 tests - All normal" (WS-05-04). The hard-coded registry ranges are also stored as if they came from the report (WS-05-08).
2. **Does anything reach the health record without confirmation?** Yes. When every group passes the auto-accept rule (`LabCandidateReconciler`, `LabReportParser.swift:716-720`) the `BloodTestResult` is saved by `linkExtractedDataToDocument` with no sheet. The user sees only a toast, "Imported N lab values / <file name>" with **Undo**, for 12 seconds (`ContentView.swift:678-684`, `:1133`). It shows no values, no date, no units, and is published *before* the commit (WS-05-12). The placeholder record (WS-05-04) also needs no confirmation. The review queue is in-memory only and does not survive Cancel or app restart (WS-05-06); the concurrency half of prior P1-13 does hold.
3. **Worst input-robustness gap**: every import rejection is silent (WS-05-05). `DocumentManager.lastError` is assigned in 12 places and read by no view, and the batch importer swallows per-file errors. Picking a 60 MB PDF, an empty file, an unsupported image type or an unreadable iCloud file does nothing visible. Close second: password-protected PDFs are misdiagnosed as "blank" and retried three times (WS-05-13).
4. **Counts**: P0=0, P1=6, P2=9, P3=0.

## Findings

### WS-05-01 — A missing unit is silently replaced by the registry default unit and the value is auto-accepted
- **Severity**: P1 · **Confidence**: CONFIRMED (parser + reconciler run; commit wiring by trace) · **Effort**: S–M
- **Location**: `Services/LabReportParser.swift:695`, `Services/DocumentProcessor.swift:1157`, `Utils/BloodTestValueValidator.swift:299-303`; same pattern at `Services/BloodTestMappingService.swift:573`, `ContentView.swift:1065`, `Views/DocumentDetailView.swift:528`
- **Scenario**: A report from a mmol/L lab (Canada, UK, EU, Australia) is OCR'd so the unit cell is lost, or the unit sits only in a column header: `Glucose  5.4  3.9-5.6`. The candidate has `unit == nil`. `unitValidation` treats a missing unit as `.valid`, the value is inside the report's own range so it is not abnormal, and the single candidate is auto-accepted. The stored item is `Glucose 5.4 mg/dL (ref 3.9-5.6)`. `ChatModels.swift:631-650` hands that line to the chat model as fact: a glucose of 5.4 mg/dL is life-threatening hypoglycaemia. The same applies to any analyte whose SI and conventional units differ by a constant factor (creatinine, calcium, cholesterol, triglycerides, vitamin D, testosterone). Harness: `Glucose  5.4  3.9-5.6` -> `AUTO: Glucose ["5.4 mg/dL [3.9-5.6]"]`; `HDL Cholesterol 55 >39` -> `AUTO ... "55 mg/dL [>39]"`.
- **Evidence**:
  ```swift
  // LabReportParser.swift:692-696
  return BloodTestImportCandidate(
      testName: candidate.parameter.name,
      value: candidate.value,
      unit: candidate.unit ?? candidate.parameter.unit,      // <- default unit written as if reported
      referenceRange: candidate.referenceRange ?? candidate.parameter.referenceRange,
  // BloodTestValueValidator.swift:299-302
  guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else {
      // Missing units remain acceptable because many reports omit units ...
      return .valid
  ```
- **Fix**: Keep "unit not reported" distinct from "unit = default". Do not auto-accept a numeric candidate with `unit == nil` unless a scale check agrees: when the report supplied a range, compare the value against the range magnitude and against the registry default range; send to review on a >5x disagreement. Never write `parameter.unit` into a stored item unless the user confirmed it, and mark inferred units (`unitInferred`) so the UI and chat context can say so.
- **Blast radius**: `LabCandidateReconciler`, the legacy `BloodTestMappingService.mapToStandardizedParameters` path, both review-completion handlers (`ContentView.swift`, `DocumentDetailView.swift` duplicate the item-building logic), `ChatModels`/`HealthContextJSON` context builders, export PDF.
- **Verification**: Unit test: `LabReportParser().parse(plainText: "Glucose  5.4  3.9-5.6")` then `LabCandidateReconciler.reconcile` must put Glucose in `needsReview`, or the saved `BloodTestItem.unit` must be nil/flagged. Repeat for `HDL Cholesterol 55 >39`.

### WS-05-02 — The urine-section state leaks into following blood sections: serum values are stored as urine analytes and auto-accepted
- **Severity**: P1 · **Confidence**: CONFIRMED (harness, real parser) · **Effort**: S–M
- **Location**: `Services/LabReportParser.swift:137` and `:168` (state seeded once per document), `:600-618` (`updateSectionTestType`)
- **Scenario**: `testType` switches to `.urine` on a urinalysis heading and returns to `.blood` only if a later heading contains one of 12 blood keywords ("hematology", "chemistry", "serum", "cbc", ...). Headings such as "Vitamins", "Iron Studies", "Hormones", "Thyroid", "Lipids" or "Inflammation" do not match. Every subsequent row is matched with `testType == .urine`, and for names that have a urine twin the matcher prefers it (`matchLabParameter`, "bare name on a urinalysis panel means urine_glucose"). The state also persists across pages (`parse(pages:)` declares it once outside the page loop). Harness, input `Urinalysis / Color Yellow / Protein Negative / Vitamins / Ferritin 30 ng/mL 15-150 / Glucose 98 mg/dL 70-99 / Creatinine 1.0 mg/dL 0.6-1.2`:
  - `Creatinine 1.0 mg/dL [0.6-1.2]` -> **`AUTO: Urine Creatinine`** (a serum value with the serum range, stored as a urine analyte, no review)
  - `Glucose 98 mg/dL` -> `REVIEW: Urine Glucose ... unitMismatch`
  - `Ferritin 30 ng/mL` -> **no candidate at all** (no urine ferritin; silently dropped)
  The record then shows "Urine Creatinine: 1.0 mg/dL (ref: 0.6-1.2)" and has no serum creatinine, which the chat model reads as a urine result.
- **Evidence**:
  ```swift
  // LabReportParser.swift:610-617
  let bloodMarkers = ["hematology", "chemistry", "complete blood count", "metabolic panel",
                      "lipid panel", "serum", "plasma", "cbc", "cmp", "bmp", "thyroid panel",
                      "coagulation", "immunology"]
  let looksLikeHeading = line.count <= 50 && !line.contains(where: { $0.isNumber })
  if looksLikeHeading && bloodMarkers.contains(where: { lowered.contains($0) }) {
      testType = .blood
  }
  ```
- **Fix**: Make urine mode sticky only until the next heading-like line (a line with no value token), not until a keyword match; require an explicit urine cue (heading or row text) for each urine match, or add a candidate-level "section was inferred" penalty that forces review. Reset the state at each page start, and when a blood-only analyte (ferritin, TSH, ...) is seen while in urine mode, switch back to blood.
- **Blast radius**: `LabReportParser` only (+ the matcher's urine preference); every deterministic import of a report that contains a urinalysis section.
- **Verification**: Unit test with the harness input above: Creatinine must match `creatinine`, Ferritin must produce a candidate, no auto-accepted `urine_*` key.

### WS-05-03 — Name-only duplicate guard plus an import-date fallback silently discards whole reports
- **Severity**: P1 · **Confidence**: CONFIRMED (trace; fixture not run) · **Effort**: M
- **Location**: `Managers/HealthDataManager.swift:276-280` and `:287-307`, `Services/DocumentProcessor.swift:989-991`, swallow sites `Managers/HealthDataManager.swift:378`, `ContentView.swift:1101`, `Views/DocumentDetailView.swift:563`
- **Scenario**: The user onboards by importing five old CMP PDFs in one sitting with the on-device extraction provider. The text LLM pass is skipped for on-device clients (`DocumentProcessor.swift` "Skipping on-device VLM text LLM pass"), so `basicInfo.testDate` is nil unless the vision pass found a date; filenames like `labs.pdf` carry none, so each report gets `testDate = document.importedAt` (today). The first saves. For reports 2-5 `findDuplicateBloodTest` sees "within 24 hours" and `calculateBloodTestSimilarity` ~1.0 (it compares result counts and test **names** only, never values) and rejects them with `validationFailed("A very similar blood test already exists for this date")`. That error is caught and logged. All five documents read "Completed"; only one report's values were saved. The same happens for two real same-day draws, and for a cloud-provider user whenever the LLM answers `TEST_DATE: unknown`. Distinct from tracker item 13, which is the swallow itself; this finding is the heuristic that creates the rejections and the date fallback that makes them common.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:989-991
  let testDate = basicInfo?.testDate
      ?? extractTestDate(from: document.fileName)
      ?? document.importedAt
  // HealthDataManager.swift:276-280
  if dateDifference < 86400 { // Within 24 hours
      let similarity = calculateBloodTestSimilarity(test, existingTest)
      if similarity > 0.8 { return existingTest }
  ```
- **Fix**: Compare values, not just names (e.g. >=80% of shared analytes with identical value+unit) before calling two tests duplicates; never apply the cross-document similarity rule when either date is a fallback (store `test_date_source: report|filename|import`); surface a skipped import as a document-level "Not imported: looks like a duplicate of <date>" state with an override.
- **Blast radius**: `HealthDataManager.addBloodTest`, both review-completion handlers, re-import/reprocess idempotency (the same-document-id rule must stay), tracker item 13.
- **Verification**: Test: two `BloodTestResult`s with identical analyte names, different values, same `testDate`, different `source_document_id` -> both saved. Import two distinct fixture reports with no extractable date -> two records, both flagged "date = import date".

### WS-05-04 — A lab/Other document with zero parsed values is saved as a real blood test containing a fake result, summarised "All normal"
- **Severity**: P1 · **Confidence**: CONFIRMED (trace) · **Effort**: S
- **Location**: `Services/DocumentProcessor.swift:795` (`isLabReport`), `:763` (`structuredData: [:]`), `:1174-1176`, `:859-862`, `:1286-1311` (`createBasicBloodTestResult`); `Models/BloodTestResult.swift:254-262` (`summary`)
- **Scenario**: The user imports a lab report whose analytes are not in the registry (hormone panel, non-English report, a poor photo that OCR'd to prose) or any document filed as "Other" (the category is treated as a lab report "for backward compatibility"). All passes return no candidates, so `createBloodTestResultFromItems` is called with `items == []`. On-device processing always passes an empty `structuredData`, so `healthDataItems` is always empty and the function returns the placeholder: `Lab Report Processed = Document imported successfully`, `isAbnormal: false`, test date = filename date or import date. It carries no `pending_review`, so `linkExtractedDataToDocument` saves it as a real record. Blood Tests then lists a test dated today, "1 tests - All normal", and the document is "Completed". Nothing tells the user that no value was read. A second placeholder within 24 h is swallowed by the WS-05-03 rule, which hides the pattern.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:1174-1176
  guard !items.isEmpty else {
      AppLog.shared.documents("No health data items found, falling back to basic blood test result", level: .warning)
      return createBasicBloodTestResult(document: document)
  // :1293-1298
  let placeholderResult = BloodTestItem(
      name: "Lab Report Processed",
      value: "Document imported successfully",
  ```
- **Fix**: Return "no lab values found" (a distinct outcome) instead of a record: do not create a `BloodTestResult` with zero real results; mark the document with a visible "No lab values recognised — review text / try cloud re-extract" state. Remove `.other` from `isLabReport`.
- **Blast radius**: `extractHealthData`, `createBloodTestResultFromItems`, `createLegacyBloodTestResult`, any UI that counts blood tests, export, AI-context blood-test picker.
- **Verification**: Process a fixture PDF containing prose only with category `.labReport` and `.other`; assert `healthDataManager.bloodTests` is unchanged and the document shows a "no values found" state.

### WS-05-05 — Every import rejection is invisible: `DocumentManager.lastError` has no reader and the batch importer swallows per-file errors
- **Severity**: P1 · **Confidence**: CONFIRMED (grep + trace) · **Effort**: S
- **Location**: `Utils/DocumentImporter.swift:331-336` (and `:343-362` validators), `Managers/DocumentManager.swift:176-187`, `ContentView.swift:937-967` and `:956`, `ContentView.swift:1002-1019`
- **Scenario**: The user picks three files from Files: a 60 MB PDF (`fileTooLarge`), a 0-byte file (`emptyFile`), an HEIF/GIF/WebP image (`DocumentType.from` -> `.other` -> `unsupportedFileType`), or a long-named/iCloud-evicted file that fails to copy (`storageError`/read error). `importMultipleDocuments` catches each error, logs it and continues; `DocumentManager.importDocuments` therefore never throws; `handleFileImportResult` only acts if `importedDocs` is non-empty. No alert, banner or sheet appears. If all files fail, nothing happens at all. The `.failure` branch of the file importer (picker error) only logs. `grep -rn lastError Views ContentView.swift` finds no reader of `DocumentManager.lastError` or `DocumentImporter.lastError`, so the same is true of queueing, delete and category-set failures. The Photos path is the same: `try? await photo.loadTransferable` drops failures (`ContentView.swift:991`).
- **Evidence**:
  ```swift
  // DocumentImporter.swift:331-336
  } catch {
      // Continue with other files even if one fails
      AppLog.shared.documents("Failed to import document: \(error.localizedDescription)", level: .error)
      lastError = error
  }
  // DocumentManager.swift:31 (only declaration; assigned at :112,:186,:211,:235,... never read by a view)
  @Published var lastError: Error?
  ```
- **Fix**: Have `importMultipleDocuments` return `(imported, failures: [(name, error)])`; present one alert listing each failed file with its `errorDescription` and `recoverySuggestion`; bind a single `.alert` to `DocumentManager.lastError` for the other flows.
- **Blast radius**: `DocumentImporter`, `DocumentManager`, `ContentView` import handlers, Photos picker path, delete/queue flows that set `lastError`. Coordinate with WS-08 (failure UX).
- **Verification**: UI/unit test: import a 0-byte file and a 51 MB file via `handleFileImportResult`; assert an error message is presented naming both files. Also import one good + one bad file and assert the good one still imports.

### WS-05-06 — The low-confidence review queue is in-memory only: Cancel or relaunch discards every extracted value of that document, including the auto-accepted ones
- **Severity**: P1 · **Confidence**: CONFIRMED (trace) · **Effort**: M
- **Location**: `Services/DocumentProcessor.swift:27`, `:31` (state), `:72-76` (`discardPendingImportReview`), `Managers/HealthDataManager.swift:369-375`, `ContentView.swift:639-643`, `Views/DocumentDetailView.swift:156-159`
- **Scenario**: A report has one value needing review, so the whole `BloodTestResult` (all auto-accepted rows too) is flagged `pending_review` and **not saved** (`HealthDataManager.swift:369`). The only handle on the pending review is `DocumentProcessor.pendingImportReview` / `pendingReviewQueue`. If the user taps Cancel (the label reads like "later"; it discards), the app is killed or crashes while the sheet is open or queued, or a second document is queued behind it and the app is relaunched, the review is gone. The document is already `.completed`; the blood test with `pending_review=true` exists only inside the document's encrypted `extracted_data`. Nothing re-opens it (`pending_review` is read nowhere else), no badge marks the document as needing review, and the "Reprocess Document" button is the only way back, with no hint that it is needed. The concurrent case of prior P1-13 holds: `enqueueImportReview` queues instead of overwriting (`:52-58`).
- **Evidence**:
  ```swift
  // HealthDataManager.swift:369-375
  if extractedBloodTest.metadata?["pending_review"] == "true" {
      AppLog.shared.healthData("Blood test has pending review - skipping save until user reviews")
      continue
  }
  // ContentView.swift:639-643
  onCancel: {
      // Cancel = discard this review; promote the next queued one.
      documentProcessor.discardPendingImportReview(for: review.documentId)
  ```
- **Fix**: Derive pending reviews from persisted state: on launch (and on document open) scan `documents.extracted_data` for a `BloodTestResult` with `pending_review == "true"` and rebuild the review (or re-run the reconciler from stored candidates); show a "Needs review" badge on the document and a Records entry point; make Cancel mean "review later". Also give the review sheet `.id(review.id)` so a promoted review never reuses the previous one's `@State` (its `autoAcceptedGroups` is captured once in `init` at `BloodTestImportReviewView.swift:27`; if the sheet is not torn down between promoted reviews, document B's confirmation would resolve document A's auto-accepted groups — PLAUSIBLE, needs a two-document device test).
- **Blast radius**: `DocumentProcessor`, `PendingImportReview`, `ContentView` + `DocumentDetailView` (both present the same sheet), `HealthDataManager.linkExtractedDataToDocument`, document list status badges.
- **Verification**: Import a report that yields a review; force-quit while the sheet is open; relaunch; the document must show "Needs review" and offer the same sheet with the same groups. Queue two reviews, Cancel the first, confirm the second still presents with its own auto-accepted list.

### WS-05-07 — A date in a neighbouring cell is taken as the reference range, so an abnormal value can be auto-accepted as normal
- **Severity**: P2 · **Confidence**: CONFIRMED (harness) · **Effort**: S
- **Location**: `Services/LabReportParser.swift:442` (first range-like cell wins), `:565-571` (`extractRange`)
- **Scenario**: Result tables with a "previous result / date" column (LabCorp, Quest, Epic exports) put a date before the range column. `extractRange` accepts any `\d{1,7}\s*[-–—]\s*\d{1,7}`, and the first match wins (`referenceRange == nil`), so a dashed date becomes the range and the real range is ignored. Harness: `Glucose  98  2024-03-12  mg/dL  70-99` -> range `2024-03`; the reconciler computes the range as 3-2024, so anything from 3 to 2024 is "normal" and the row is `AUTO` accepted. `Glucose 98 03-12-2023 mg/dL 70-99` -> range `03-12` (value reads abnormal, goes to review, wrong range shown). The stored item and chat context carry `(ref: 2024-03)`. A genuinely abnormal value (glucose 250) with no flag column is auto-accepted as normal.
- **Evidence**:
  ```swift
  // LabReportParser.swift:568-571
  let intervalPattern = #"\d{1,7}(\.\d+)?\s*[-–—]\s*\d{1,7}(\.\d+)?"#
  if let match = trimmed.range(of: intervalPattern, options: .regularExpression) {
      return String(trimmed[match]).replacingOccurrences(of: " ", with: "")
  ```
- **Fix**: Anchor the interval pattern to the whole cell (`^...$`, optionally followed by a unit), reject candidates whose bounds look like a date (year-like >1900 with a 2-digit month, or two 2-digit numbers separated by `-` that is part of `\d{2}-\d{2}-\d{4}`), and prefer the cell under a "Reference" header when column labels are known.
- **Blast radius**: `LabReportParser.parseRowCells`, `extractUnit`, every deterministic import.
- **Verification**: Unit tests with the two harness rows above plus `Glucose 250 2024-03-12 mg/dL 70-99` (must not be auto-accepted).

### WS-05-08 — Registry defaults are stored as if the report said them; spaced ranges are lost; a mmol/L value is compared with a mg/dL range
- **Severity**: P2 · **Confidence**: CONFIRMED (harness) · **Effort**: M
- **Location**: `Services/LabReportParser.swift:90`, `:456`, `:696`; `Models/BloodTestResult.swift:404-409` (defaults), `Services/DocumentProcessor.swift:1158`
- **Scenario**: (a) A space-separated line `Glucose 98 mg/dL 70 - 99` splits the range into three tokens, so no range is found; the item is saved with the app's `70-100`, not the report's `70-99`. (b) Defaults are single, non-sex/age-specific (Hemoglobin `12.0-16.0`, Hematocrit `36-46`, Creatinine `0.6-1.2`); a male hemoglobin of 12.5 is "normal" and a female 16.5 abnormal using the wrong sex's range, and the stored item has no marker that the range is the app's. (c) `Glucose  5.4  mmol/L` with no range -> `unitMismatch`, but the candidate carries `abn=true` computed against `70-100` mg/dL and the review row shows `Expected: 70-100`. If the user taps "Unit Warning — tap to import", the record holds `5.4 mmol/L (ref: 70-100) [ABNORMAL]`, an internally inconsistent line that is sent to the chat model. Harness: `AUTO: Glucose ["98 mg/dL [70-100]"]`; `REVIEW: Glucose ["5.4 mmol/L [70-100] unitMismatch"]`.
- **Evidence**:
  ```swift
  // LabReportParser.swift:87-92
  var isAbnormal: Bool {
      BloodTestValueValidator.isAbnormal(
          value: value,
          referenceRange: referenceRange ?? parameter.referenceRange,   // default range even when unit disagrees
  ```
- **Fix**: Add `referenceRangeSource` (`report|app_default|none`) to `BloodTestItem`; use the default only for display ("typical adult range") and never to compute `isAbnormal` when the unit is missing/mismatched; join `70 - 99` style ranges in the single-space tokenizer; keep sex/age ranges out of scope but label the default clearly.
- **Blast radius**: `LabValueCandidate.isAbnormal`, `LabCandidateReconciler`, `BloodTestItem` Codable (optional field = no migration), review UI, context builders.
- **Verification**: Parse the three harness rows; assert range `70-99` is captured, a defaulted range is labelled, and a mismatched-unit candidate is not `isAbnormal` from default ranges.

### WS-05-09 — Decimal-comma and thousands handling: `5,4` is read as 54, ranges are garbled, and the value is stored as written
- **Severity**: P2 · **Confidence**: CONFIRMED (harness) · **Effort**: M
- **Location**: `Utils/BloodTestValueValidator.swift:156-166` (`numericValue`), `:254-282` (`parseReferenceRange`), `Services/LabReportParser.swift:520` (`isValueToken`), `:568` (`extractRange`)
- **Scenario**: `isValueToken` accepts `\d+[.,]\d+`, then `numericValue` deletes every comma, so `5,4` becomes 54 and `1,2` becomes 12. A decimal-comma report (Germany, France, Brazil, much of Europe, LATAM) therefore gets inflated numbers for abnormal evaluation, and its ranges are mangled (`3,9-5,6` -> `9-5`; `150,000-450,000` -> `000-450`). Because the inflated value is almost always "outside" the range, the rows land in review with an abnormal badge and default to "Will Ignore" (WS-05-11); the values are stored as the literal string `5,4`. Thousands (`250,000`) is read correctly as a number but is shown next to the registry unit `K/uL` (a 250-million platelet count). Harness: `Creatinine 1,2 mg/dL 0.6-1.2` -> `abn=true`; `Glucose 5,4 mmol/L 3,9-5,6` -> range `9-5`; `Platelet Count 250,000 /uL 150,000-450,000` -> range `000-450`, shown as `250,000 K/uL`.
- **Evidence**:
  ```swift
  // BloodTestValueValidator.swift:158-165
  cleaned = cleaned
      .replacingOccurrences(of: "<", with: "")
      ...
      .replacingOccurrences(of: ",", with: "")      // "5,4" -> "54"
  return Double(cleaned)
  ```
- **Fix**: Disambiguate: a comma followed by exactly three digits and a preceding 1-3 digit group is a thousands separator; otherwise treat comma as decimal and normalise at parse time (store a canonical dot-decimal value plus `rawValue`). Apply the same to range parsing; convert `/uL` count units rather than relabelling.
- **Blast radius**: validator (also used by the LLM and vision paths), reconciler key `normalizedValueKey`, review display.
- **Verification**: Table-driven tests: `5,4 -> 5.4`, `1,234 -> 1234`, `250,000 -> 250000`, range `3,9-5,6 -> (3.9,5.6)`; plus a decimal-comma fixture report producing no auto-accepted wrong values.

### WS-05-10 — Test date: the lab-draw date is never prioritised, the AI date is discarded by a formatter bug, the fallback is the import date, and the user is never shown it
- **Severity**: P2 · **Confidence**: CONFIRMED (formatter behaviour run; wiring by trace) · **Effort**: M
- **Location**: `Services/MedicalDocumentExtractor.swift:623`, `:284-316`; `Services/BloodTestMappingService.swift:147` and `:812-827`; `Services/DocumentProcessor.swift:1530-1541`, `:1885-1907`; `Services/LabReportParser.swift:794`; `Views/BloodTestImportReviewView.swift` (no date field)
- **Scenario**: (1) The AI document date is requested as `YYYY-MM-DD` but parsed with `ISO8601DateFormatter().date(from:)`, whose default options need a full date-time; a date-only string returns `nil` (verified: `2024-03-12` -> nil, `2024-03-12T00:00:00Z` -> valid). The AI date is therefore always dropped and the code falls back to the first `MM/dd/yyyy` found anywhere in the text, which on a lab report is frequently the patient's date of birth or a print date. (2) The blood-test date prompt asks for "Test/Report Date ... Collection Date"; collection vs report vs received dates are not ranked, so which one wins is up to the model. (3) Filename dates in `DocumentProcessor.extractTestDate` are parsed with the device-locale `.short` style: `03-12-2023` is 12 March on en_US and 3 December on en_GB (verified); `BloodTestMappingService.parseDate` tries `MM/dd` before `dd/MM`, and `04/03/23` parses as year 0023 (verified). (4) If nothing is found the date silently becomes the import date, and the review sheet and the 12 s toast never show a date. (5) Dates are midnight in the local zone, so a record can display a day earlier after the user changes time zones westward (P3 aspect).
- **Evidence**:
  ```swift
  // MedicalDocumentExtractor.swift:621-627
  if let dateString = json?["document_date"] as? String,
     let date = ISO8601DateFormatter().date(from: dateString) {      // "YYYY-MM-DD" -> nil
      documentDate = date
  } else {
      documentDate = extractDateFromFileName(fileName) ?? extractDateFromText(fallbackText)   // first date in text
  ```
- **Fix**: Parse AI dates with `yyyy-MM-dd` + POSIX locale + UTC noon; prefer "collected" > "reported" with explicit labels in the text pass; use POSIX parsing for filename dates; carry `test_date_source` and show the date (editable) in the review sheet and toast; exclude dates adjacent to "DOB/Birth/Printed".
- **Blast radius**: `MedicalDocumentExtractor`, `BloodTestMappingService`, `DocumentProcessor`, review UI, document sorting and chat context ordering, WS-05-03.
- **Verification**: Unit tests for `parseAIResponse` with `document_date: "2024-03-12"`; filename `Lab 03-12-2023.pdf` under en_US and en_GB locales; fixture with DOB before the collection date.

### WS-05-11 — Abnormal results default to "Will Ignore"; one tap on "Import Selected" produces a record that reports "All normal"
- **Severity**: P2 · **Confidence**: CONFIRMED (trace) · **Effort**: S
- **Location**: `Models/DuplicateBloodTestCandidate.swift:85-87` and `:139-144`, `Views/BloodTestImportReviewView.swift:66-73`, `:152-154`, `:466-479`, `Models/BloodTestResult.swift:254-262`
- **Scenario**: `isRecommended` requires `!isAbnormal`, and a group's default selection is its recommended candidate. Every abnormal result is therefore unselected, and `onAppear` puts it in `ignoredGroupIds`, labelled "Will Ignore". The primary toolbar button is "Import Selected" and the header button "Accept All Recommended" also excludes them. A user who accepts the sheet as presented saves only the normal values (plus auto-accepted normals); `BloodTestResult.summary` then reads "N tests - All normal" for a report whose clinically important rows were dropped. Abnormal results are exactly the ones a health app must not drop by default, and the copy ("Please review values before importing") does not say that abnormal rows need a tap.
- **Evidence**:
  ```swift
  // DuplicateBloodTestCandidate.swift:85-87
  var isRecommended: Bool {
      return validationStatus == .valid && !isAbnormal && confidence > 0.7
  }
  // BloodTestImportReviewView.swift:66-73
  for group in importGroups {
      if let selectedCandidateId = group.selectedCandidateId { selectedIds[group.id] = selectedCandidateId }
      else { ignoredGroupIds.insert(group.id) }
  ```
- **Fix**: Preselect the single valid abnormal candidate (abnormal needs *visibility*, not exclusion); keep multi-value and unit-mismatch groups unselected; show a count banner "3 abnormal results will be imported / 2 ignored" and disable "Import Selected" while any group is undecided.
- **Blast radius**: `BloodTestImportGroup.init`, review view, the two completion handlers, tests asserting current defaults.
- **Verification**: UI test: import a fixture with one abnormal glucose; tap Import Selected with no other interaction; the saved record must contain glucose flagged abnormal.

### WS-05-12 — The auto-import toast is published before the commit and says nothing about what was imported
- **Severity**: P2 · **Confidence**: CONFIRMED (trace) · **Effort**: S–M
- **Location**: `Services/DocumentProcessor.swift:1014-1022` (summary published) vs `:554-562` (commit), `ContentView.swift:672-686`, `:1125-1172`
- **Scenario**: `lastAutoImportSummary` is set while the lab pipeline is still running; the medical-document extraction (cloud call on non-MLX clients), the document save and `linkExtractedDataToDocument` come after it. If the run is then cancelled or fails, or the commit is rejected (WS-05-03 duplicate rule, tracker item 13 `validationFailed`), the toast "Imported 12 lab values from labs.pdf" has already been shown. Tapping Undo then finds no matching record and only logs. The toast lasts 12 s, lives on `ContentView` (not visible if the user is on another screen or the app is backgrounded), shows no values, units or test date, and offers no "View" action although the code comment promises "View | Undo". This is the entire user-facing confirmation for values that bypass review.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:1014-1022
  AppLog.shared.documents("All \(reconciled.autoAccepted.count) values auto-accepted — importing silently")
  lastAutoImportSummary = AutoImportSummary(
      documentId: document.id, documentName: document.fileName,
      bloodTestId: bloodTest.id, importedCount: bloodTest.results.count)
  ```
- **Fix**: Publish the summary from `linkExtractedDataToDocument` after `addBloodTest` succeeds (and only then); include test date and the first abnormal values; add a "View" action; keep a persistent per-document "Imported N values on <date> · Undo" row in the document detail.
- **Blast radius**: `DocumentProcessor`, `HealthDataManager.linkExtractedDataToDocument`, `ContentView` banner, `AutoImportSummary`.
- **Verification**: Reprocess an already-imported document (commit rejected as same-document duplicate): no toast must appear; fresh import: toast appears only after the record exists.

### WS-05-13 — Status machine holes: pause leaves a document stuck at `.processing`, deterministic failures are retried three times, progress is meaningless, the timeout is dead code
- **Severity**: P2 · **Confidence**: CONFIRMED (trace; PDFKit behaviour run) · **Effort**: M
- **Location**: `Services/DocumentProcessor.swift:335-360` (pause/clear), `:618-630` (retry branch), `:1610-1619` (`updateProcessingProgress`), `:105` (`processingTimeout`); `Services/NativeDocumentExtractor.swift:289-300`, `:391`
- **Scenario**: (a) A failure schedules a retry but writes no status; the row stays `.processing` for the 2-4 s delay (`:620-630`). If the user taps Pause/Clear in that window, `pauseProcessing` cancels `retryTasks` and `clearQueue` resets only items in `processingQueue`, so the document remains `.processing` with no task. The UI shows a spinner and offers no action (Retry exists only for `.failed`, Process for `.pending`, Reprocess for `.completed`) until the next launch maps it to `.failed` (`:1686-1690`). (b) Every error except cancellation is retried, including deterministic ones: a password-protected PDF (PDFKit loads it with `isLocked == true`, `page.string == nil`, the page renders blank, so extraction ends in `allPagesEmpty` "document may be blank or too low quality... re-scan"), `pdfLoadFailed`, `emptyDocument`, `documentNotFound`. Each attempt repeats full 300-DPI OCR of up to 50 pages; the failure notification arrives only after the third attempt, and the message for a locked PDF is wrong (`isLocked` is never checked). (c) `updateProcessingProgress` sets `completed = processingTasks.count` (the number currently *running*), so progress is 100% at the start of a single-document run and falls as work completes. (d) `processingTimeout = 300` is declared and never enforced.
- **Evidence**:
  ```swift
  // DocumentProcessor.swift:618-630  (no updateDocumentStatus in this branch)
  if currentItem.retryCount < maxRetryAttempts {
      currentItem.status = .retrying
      ...
      retryTasks[currentItem.document.id] = Task { try? await Task.sleep(...); await self.addToQueue(...) }
  // :1611-1612
  let totalItems = processingQueue.count + processingTasks.count
  let completedItems = max(0, processingTasks.count)
  ```
- **Fix**: Persist `.queued` (or a `retrying` marker) when scheduling a retry, and reset retry-pending documents to `.pending` in `pauseProcessing`/`clearQueue`; classify errors (`nativeExtractionFailed(pdfLoadFailed|emptyDocument|allPagesEmpty)`, `documentNotFound`, locked PDF) as non-retryable and fail fast with specific copy ("This PDF is password-protected"); check `PDFDocument.isLocked` on load; compute progress from real stage/page counts; enforce or delete the timeout.
- **Blast radius**: `DocumentProcessor` (serialises with tracker items 5 and 13), `NativeDocumentExtractor`, failure notification copy, `BatchProcessingView`.
- **Verification**: Test: force one failure, call `pauseProcessing()` within the delay, assert the stored status is `.pending`. Fixture: `locked.pdf` -> fails once with a "password-protected" message and `processingErrors.count == 1`.

### WS-05-14 — Partial extraction is reported as complete success
- **Severity**: P2 · **Confidence**: CONFIRMED (cap and chunk catch by trace; two-column by harness) · **Effort**: M
- **Location**: `Services/NativeDocumentExtractor.swift:169` and `:296`; `Services/LabReportParser.swift:368-380` and `:274-298`; `Services/BloodTestMappingService.swift:396-401`; `Services/DocumentProcessor.swift:1060`
- **Scenario**: (a) Only the first 50 pages are read (`maxPages = 50`); a 120-page record set imports as `page_count = 50`, status Completed, with no warning anywhere. (b) The on-device vision pass reads only 6 pages (`maxOnDevicePages`) and logs it. (c) Side-by-side layouts: rows are grouped by Y only and `parseRowCells` takes the first value in the row, so `Glucose 98 mg/dL 70-99  Sodium 140 mmol/L 135-145` on one visual row yields Glucose only; the second analyte is dropped silently (harness). (d) In the cloud text pass each 2000-character chunk that throws returns `[]` and the others continue (`catch ... return []`), so a transient error mid-document drops a slice of the report with no signal. The toast then says "Imported 7 lab values". The parser's confidence gives no indication of coverage.
- **Evidence**:
  ```swift
  // NativeDocumentExtractor.swift:169, 296
  private let maxPages = 50
  let pageCount = min(pdfDocument.pageCount, maxPages)
  // BloodTestMappingService.swift:396-401
  } catch {
      // If chunk processing fails, return empty array rather than failing entirely
      return []
  ```
- **Fix**: Carry `pagesTotal/pagesRead` and `chunksFailed` in the extraction metadata and surface "Read 50 of 120 pages" / "2 sections could not be read" on the document and in the toast; split a row at repeated name/value groupings into multiple candidates; retry failed chunks once.
- **Blast radius**: `ExtractionResult`, `ProcessedDocumentResult.metadata`, document detail, toast.
- **Verification**: Fixture with 60 pages -> document shows "50 of 60 pages"; inject a failing client for chunk 2 -> document shows a warning; harness row with two analytes -> two candidates.

### WS-05-15 — File lifecycle: delete can leave encrypted originals behind and still report success; nothing ever reclaims orphans
- **Severity**: P2 · **Confidence**: CONFIRMED (trace) · **Effort**: M
- **Location**: `Managers/DocumentManager.swift:365-403`, `:501-513`; `Utils/FileSystemManager.swift:204-214`, `:259-265`, `:308-314`, `:437-455`; `Utils/DocumentImporter.swift:111-136`
- **Scenario**: (a) `deleteDocument` removes the DB row first, then removes the file only `if FileManager.default.fileExists(atPath: document.filePath.path)` and swallows removal errors, then returns `true`. File and thumbnail paths are stored as absolute URLs (`DatabaseManager+Documents.swift:42-47`; WS-02-10); after a container-path change (restore, reinstall, simulator) the check fails, the encrypted original stays on disk, and the UI reports a successful delete. (b) `cleanupOrphanedFiles` is never called and, if it were, treats `DocumentManager.documents` as the keep-list (a filtered or not-yet-loaded array would delete everything), so there is no garbage collection at all. (c) Import writes the encrypted file first and the DB row afterwards (`DocumentImporter.swift:111-136`); a failure between them (DB error, crash) leaves an unreferenced file. (d) `FileSystemManager.storeThumbnail` names files `<documentId>_thumb.jpg` while `deleteDocument(at:)` removes `<storedName>_thumb.jpg`; only the former naming is deleted by `deleteDocument(at:)`, the latter relies on the `thumbnail_path` fallback. (e) The PDF thumbnail draws with `scaleBy(200/w, 200/h)` and no vertical flip or aspect preservation (`FileSystemManager.swift:259-265`), so PDF thumbnails are distorted and probably upside-down (UIKit y-axis; PLAUSIBLE, not rendered). Plaintext thumbnails and original filenames in backups are already filed (WS-07-02, WS-01-07) and are not repeated here.
- **Evidence**:
  ```swift
  // DocumentManager.swift:380-386
  if FileManager.default.fileExists(atPath: document.filePath.path) {
      do { try fileSystemManager.deleteDocument(at: document.filePath) }
      catch { AppLog.shared.documents("Failed to remove source file ...", level: .warning) }
  }
  ...
  return true
  ```
- **Fix**: Store paths relative to the documents directory and resolve at use (also fixes share/QuickLook after a container change); delete the file by the stored file name via `findDocumentByFileName` when the absolute path is stale; return/log failure when the file cannot be removed; add a launch-time orphan sweep driven by the DB (document file names + thumbnails), never by an in-memory list; fix the PDF thumbnail transform.
- **Blast radius**: `DocumentManager`, `FileSystemManager`, `DatabaseManager+Documents` path columns (migration needed for relative paths; WS-02-10), share/QuickLook paths.
- **Verification**: Test: create a document, change the stored `file_path` prefix, call `deleteDocument`; the encrypted blob must be gone. Crash-injection test between `storeDocument` and `saveDocument`; the sweep must remove the file.

## Status transition table

Persisted `ProcessingStatus` = `pending | queued | processing | completed | failed` (`Models/HealthDocument.swift:75`). In-memory `ProcessingItemStatus` adds `retrying` and is never persisted. Every write site of the persisted status:

| From -> To | Written at | Guard / notes |
|---|---|---|
| (new) -> `pending` | `Models/MedicalDocument.swift:73` default; `DocumentImporter.swift:136/218/291` `saveDocument` | none; imported before the user picks a category, processing starts only after `setDocumentCategoryAndProcess` |
| `pending`/`failed`/`completed` -> `queued` | `DocumentProcessor.swift:155` (`addToQueue`) | dedupe on queue + `processingTasks`; DB error swallowed (logged only); also used for Retry and Reprocess, so a `completed` document drops out of `.completed`-only lists (AI-context selector, `UnifiedContextSelectorView.swift:897`) while reprocessing |
| `queued` -> `queued` (relaunch) | `:1692-1695` | re-queued automatically at launch |
| `queued` -> `processing` | `:372` | throws `notFound` if the row was deleted, which is treated as a processing failure and retried |
| `processing` -> `completed` | `:449`/`:505` (`saveMedicalDocument`, full-row `INSERT OR REPLACE`); `DatabaseManager+Documents.swift:189` (`updateDocumentExtractedData`) | checkpoints at `:382`, `:395`, `:554`; row is marked `completed` **before** `linkExtractedDataToDocument` runs, so a link failure leaves `completed` data and then flips to retry/failed. Tracker item 5 is the stale-snapshot overwrite here |
| `processing` -> `processing` (retry wait, 2-4 s) | no write (`:618-630`) | **hole**: Pause/Clear in this window strands the row (WS-05-13) |
| `processing` -> `pending` | `:583` (cancel catch); `:184` (`removeFromQueue`); `:356` (`clearQueue`, queued items only) | cancel never retries; OCR/Vision do not observe cancellation (WS-03-09) so the task runs to the next checkpoint first; a cancelled reprocess leaves previously good data under a `pending` badge |
| `processing`/retry -> `failed` | `:637` after 3 attempts | all non-cancel errors are retried, including deterministic ones (WS-05-13) |
| `processing` -> `failed` (relaunch) | `:1686-1690` | recovery for crash/force-quit; `queued` rows are re-queued |
| `completed` -> `failed`/`pending` | same sites as above | only via reprocess |
| any -> (row deleted) | `DocumentManager.swift:373` | `removeFromQueue` first (`:368`) cancels the task and the post-OCR/post-LLM checkpoints stop the write-back; tracker item 5 describes the remaining window |

Illegal or undefined transitions found: (1) retry-wait -> stuck `processing` (above); (2) `.completed` written before the health-data link; (3) no state for "needs review" or "no values found" (WS-05-04, WS-05-06), so the UI cannot express either.

## Input robustness table

| Input | Observed behaviour (code-trace unless noted) | file:line | Severity |
|---|---|---|---|
| Password-protected PDF | PDFKit loads it (`isLocked == true`, `pageCount` 1, `page.string == nil`; run on macOS PDFKit with `scratchpad/inputs/locked.pdf`); page renders blank; OCR finds nothing; `allPagesEmpty` "blank or too low quality... re-scan" after 3 retries. `isLocked` never checked | `NativeDocumentExtractor.swift:289-300`, `:353`, `:391`; `DocumentProcessor.swift:618` | P2 (WS-05-13) |
| 0-byte file | Importer rejects with `emptyFile`, but nothing is shown | `DocumentImporter.swift:352-362`; `DocumentManager.swift:176` | P1 (WS-05-05) |
| `.pdf` that is really a JPEG | `PDFDocument(data:)` returns nil (run); `pdfLoadFailed` "corrupted or password-protected", retried 3x; type comes from the extension only | `NativeDocumentExtractor.swift:289`; `DocumentImporter.swift:70` | P3 |
| 400 MB PDF | Rejected at 50 MB with `fileTooLarge`, silently; the camera-scan path has no size check | `DocumentImporter.swift:352-357`; scan path `:177-200` has no size check | P1 (WS-05-05) |
| 500-page PDF (<50 MB) | First 50 pages only, `page_count = 50`, status Completed, no warning | `NativeDocumentExtractor.swift:169`, `:296` | P2 (WS-05-14) |
| PDF page fails to render (prior P0-1) | Per-page `catch` keeps PDFKit text and continues; `page(at:)` nil is guarded. Holds | `NativeDocumentExtractor.swift:309-312`, per-page catch in OCR loop | OK |
| HEIC with unusual colour profile | No explicit colour management; `UIImage(data:).cgImage` goes straight to Vision/CIFilters; no failure path identified. Unmeasured: 48 MP images allocate several full-size copies via two `CIContext()` per image | `NativeDocumentExtractor.swift:416`, `:631`, `:646` | P3 (unverified) |
| Phone photo with EXIF orientation | `uiImage.cgImage` ignores `imageOrientation`; `VNImageRequestHandler` is created without an orientation (`:506`). Vision still read rotated lines in a macOS test, but each line's box then spans the page height, so the geometry-based row grouping and table detection cannot work; deterministic parse yields nothing and falls to LLM/VLM. Fix: pass the orientation or normalise on import | `NativeDocumentExtractor.swift:416`, `:506`, `:605` | P3 (PLAUSIBLE) |
| Angled photo of a lab report | Document-segmentation + perspective correction when confidence >0.8, otherwise raw image; no failure path | `NativeDocumentExtractor.swift:584-650` | OK |
| DOCX (with or without text) | Not reachable: the picker allows `[.pdf, .image]` only; if a `.docx` arrived, extraction hands the bytes to PDFKit, which returns nil, so it would fail `pdfLoadFailed`. The importer error text and CLAUDE.md still claim Word support | `ContentView.swift:592`; `NativeDocumentExtractor.swift:244`, `:272`; `DocumentImporter.swift:343-347` | P3 (claim drift) |
| Scanned page with no text | OCR returns no observations -> `allPagesEmpty`, retried 3x, then Failed with a clear message | `NativeDocumentExtractor.swift:353`, `:391`, `:432` | P3 |
| File deleted from Files mid-import | `Data(contentsOf:)` throws; `storageError`; swallowed (nothing shown). After the copy completes there is no further dependency on the source | `FileSystemManager.swift:317-320`; `DocumentImporter.swift:111-118` | P1 (WS-05-05) |
| iCloud-evicted file | `copyFile` reads the URL with `Data(contentsOf:)` on the main actor with no `NSFileCoordinator`; either blocks the UI while the provider materialises up to 50 MB, or fails and is swallowed. PLAUSIBLE; not reproducible without a device | `FileSystemManager.swift:317-320`; WS-03-07 | P2 |
| Non-Latin / mixed-script text | OCR is pinned to `["en-US"]`; the lab registry and aliases are English only, so such reports yield zero candidates and (for Lab/Other) the placeholder blood test | `NativeDocumentExtractor.swift:499`; WS-05-04 | P2 |
| Two-column layout | Only the first analyte per visual row is parsed (harness) | `LabReportParser.swift:368-380` | P2 (WS-05-14) |
| Ligatures / embedded-text PDFs | OCR geometry is attached to every page, so the parser uses observations rather than `page.string`; ligature glyphs only matter on the plain-text fallback | `NativeDocumentExtractor.swift:347-368` | P3 (unverified) |
| Very large page size (poster) | Pages are rasterised at 300 DPI with no pixel cap: a 36x48 in page is 10800x14400 px (~620 MB) before OCR copies | `NativeDocumentExtractor.swift:739-760` | P3 (PLAUSIBLE) |
| Very long file name | `UUID_` + sanitised name has no length cap; an APFS name-too-long write error maps to `storageError`, swallowed | `FileSystemManager.swift:125-135`, `:501-504` | P3 (PLAUSIBLE) |

Vision continuation double-resume (`NativeDocumentExtractor`, tracker item 1) is deliberately not re-reported.

## Prior-finding verification (this workstream's items)

| Prior | Result | Evidence |
|---|---|---|
| P1-7 reprocess preserves user metadata / AI-context toggle | Holds | `DocumentProcessor.swift:405-480` merges `existingDocument` for date, provider, tags, notes, `includeInAIContext`, priority, `lastEditedAt` |
| P1-8 pause/clear restarts silently | Holds for retry timers (`retryTasks` cancelled); see WS-05-13 for the stranded-row hole | `:341-346` |
| P1-10 share hands out the encrypted blob | Holds: share decrypts to a temp copy, QuickLook decrypts in its coordinator | `Views/DocumentDetailView.swift:80-93`, `:711-` |
| P1-11 "Export PDF report" produces real pages | Holds by code trace (explicit `beginPage()`, paginated blocks). Not rendered | `Utils/DocumentExporter.swift:246-300` |
| P1-13 single in-memory review slot | Concurrent half holds (queue); durability half does not (WS-05-06) | `DocumentProcessor.swift:52-76` |
| P1-14 `thumbnail_path` nulled on processing | Holds: `thumbnailPath: existingDocument?.thumbnailPath ?? ...` | `:441-443` |
| P1-15 multi-file selection | Holds: all imported documents are appended to `pendingCategoryDocuments`; the serialisation cost is already filed (WS-03-04) | `ContentView.swift:956-964` |

## Structural risks

- The registry doubles as the source of truth for units, ranges and display names, with no field recording whether a stored unit/range was *reported* or *defaulted*. Four findings (01, 07, 08, 09) share this root; a `source` attribute on `BloodTestItem` (optional, no migration) is the single change that makes most of them detectable downstream.
- Three extraction paths (deterministic parser, cloud text LLM, VLM) plus a legacy mapping path (`BloodTestMappingService.mapDocumentToBloodTest`) each implement their own date, unit-default and range logic. The legacy path is reached only when no candidates exist and always ends in forced review or the placeholder; consider deleting it.
- Review state (pending reviews, auto-import summary, retry timers) lives in `DocumentProcessor` memory while the data it governs is persisted; any restart or navigation edge loses the link. A persisted "needs review" status would cover WS-05-06 and the missing UI states in the status table.
- The item-building code for a confirmed review is duplicated in `ContentView.handleImportReviewComplete` and `DocumentDetailView` (and again in `bloodTestItems(from:)`); the three copies already agree on the unit-defaulting bug and will drift on any fix.
- `DocumentProcessor.swift` (1,957 lines) mixes queue control, OCR orchestration, lab reconciliation, genetic parsing, notifications and date/measurement helpers; fixes for tracker items 5/13 and findings 03, 04, 12, 13 all touch it and must be serialised.

## Machine-readable summary
```json
[
  {"id":"WS-05-01","title":"Missing unit replaced by registry default unit; value auto-accepted","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/LabReportParser.swift:695","HealthApp/HealthApp/Services/DocumentProcessor.swift:1157","HealthApp/HealthApp/Utils/BloodTestValueValidator.swift:299"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-02","title":"Urine section state leaks: serum values stored as urine analytes, others dropped","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/LabReportParser.swift:600","HealthApp/HealthApp/Services/LabReportParser.swift:137"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-03","title":"Name-only duplicate guard plus import-date fallback silently drops whole reports","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/HealthDataManager.swift:276","HealthApp/HealthApp/Services/DocumentProcessor.swift:989"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-04","title":"Zero-value lab/Other document saved as real blood test with placeholder result, 'All normal'","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:795","HealthApp/HealthApp/Services/DocumentProcessor.swift:1174","HealthApp/HealthApp/Services/DocumentProcessor.swift:1293"],"effort":"S","area":"document-pipeline"},
  {"id":"WS-05-05","title":"All import rejections invisible: DocumentManager.lastError unread, batch importer swallows errors","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/DocumentImporter.swift:331","HealthApp/HealthApp/Managers/DocumentManager.swift:176","HealthApp/HealthApp/ContentView.swift:956"],"effort":"S","area":"document-pipeline"},
  {"id":"WS-05-06","title":"Review queue is in-memory only: Cancel/relaunch discards extracted values incl. auto-accepted","severity":"P1","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:31","HealthApp/HealthApp/Managers/HealthDataManager.swift:369","HealthApp/HealthApp/ContentView.swift:639"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-07","title":"Date in neighbouring cell parsed as reference range","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/LabReportParser.swift:442","HealthApp/HealthApp/Services/LabReportParser.swift:568"],"effort":"S","area":"document-pipeline"},
  {"id":"WS-05-08","title":"Registry default ranges stored as report ranges; spaced ranges lost; cross-unit abnormal flag","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/LabReportParser.swift:90","HealthApp/HealthApp/Services/LabReportParser.swift:696","HealthApp/HealthApp/Models/BloodTestResult.swift:404"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-09","title":"Decimal comma read as thousands (5,4 -> 54); ranges garbled","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Utils/BloodTestValueValidator.swift:156","HealthApp/HealthApp/Services/LabReportParser.swift:520"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-10","title":"Test date: ISO8601 date-only parse returns nil, DOB risk, locale-dependent filename parse, import-date fallback never shown","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/MedicalDocumentExtractor.swift:623","HealthApp/HealthApp/Services/DocumentProcessor.swift:1530","HealthApp/HealthApp/Services/BloodTestMappingService.swift:812"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-11","title":"Abnormal results default to Will Ignore; Import Selected yields 'All normal' record","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Models/DuplicateBloodTestCandidate.swift:85","HealthApp/HealthApp/Views/BloodTestImportReviewView.swift:66"],"effort":"S","area":"document-pipeline"},
  {"id":"WS-05-12","title":"Auto-import toast published before commit and shows only a count","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:1014","HealthApp/HealthApp/ContentView.swift:672"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-13","title":"Status machine holes: stuck processing after pause, deterministic failures retried, bogus progress, dead timeout","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/DocumentProcessor.swift:335","HealthApp/HealthApp/Services/DocumentProcessor.swift:618","HealthApp/HealthApp/Services/DocumentProcessor.swift:1610","HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:289"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-14","title":"Partial extraction reported as complete success (50-page cap, two-column rows, failed chunks)","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Services/NativeDocumentExtractor.swift:296","HealthApp/HealthApp/Services/LabReportParser.swift:368","HealthApp/HealthApp/Services/BloodTestMappingService.swift:396"],"effort":"M","area":"document-pipeline"},
  {"id":"WS-05-15","title":"Delete can leave encrypted originals and report success; no orphan GC; thumbnail naming/transform issues","severity":"P2","confidence":"CONFIRMED","files":["HealthApp/HealthApp/Managers/DocumentManager.swift:365","HealthApp/HealthApp/Utils/FileSystemManager.swift:204","HealthApp/HealthApp/Utils/FileSystemManager.swift:437"],"effort":"M","area":"document-pipeline"}
]
```
