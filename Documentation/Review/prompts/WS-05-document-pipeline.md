# WS-05 — Document import & extraction pipeline

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-05-document-pipeline.md`**

Document import is the app's most complex stateful flow and the source of most of the
prior review's P1s. It touches the file system, OCR, parsing, the database, and the UI
simultaneously, and it runs for a long time while the user does other things.

## Scope

- `HealthApp/HealthApp/Services/DocumentProcessor.swift` (~1,960 LOC — the core)
- `HealthApp/HealthApp/Services/NativeDocumentExtractor.swift` (~920 LOC)
- `HealthApp/HealthApp/Services/MedicalDocumentExtractor.swift` (~720 LOC)
- `HealthApp/HealthApp/Services/LabReportParser.swift` (~930 LOC)
- `HealthApp/HealthApp/Services/BloodTestMappingService.swift` (~960 LOC)
- `HealthApp/HealthApp/Managers/DocumentManager.swift`
- `HealthApp/HealthApp/Utils/FileSystemManager.swift` (~730 LOC)
- Views: `DocumentListView`, `DocumentGridView`, `DocumentDetailView`,
  `MedicalDocumentDetailView`, `BatchProcessingView`, `DocumentCameraView`,
  `BloodTestImportReviewView`

## What to examine

**State machine.** Enumerate every document status the code can set and draw the legal
transitions. Then find every path that writes a status and check it against the diagram.
Specifically:
1. Can a document be left in `.processing` forever (app killed, crash, cancellation,
   backgrounding)? Is there recovery on next launch?
2. Delete-while-processing: does the row come back? Does the file?
3. Reprocess: does it preserve user-entered metadata and the AI-context toggle, or
   overwrite them? (Prior P1-7.)
4. Multi-file selection: are all files processed, or only the first? (Prior P1-15.)

**Input robustness.** For each of these inputs, trace what happens — crash, silent
failure, or a clear error:
- Encrypted/password-protected PDF
- PDF whose page fails to render (prior P0-1 was an index crash here)
- 0-byte file; a `.pdf` that is actually a JPEG; a 400 MB PDF; a 500-page PDF
- HEIC from the camera with an unusual colour profile; a photo of a lab report at an angle
- A DOCX with no extractable text; a scanned page with no text at all
- A file the user deletes from Files.app mid-import; an iCloud-evicted file that needs download
- Non-English / mixed-script text; PDFs with ligatures or two-column layouts

**File system.** Where do originals, thumbnails, and derived artifacts live? Are they
inside the app container, excluded from backup per the project's local-only stance, and
cleaned up when the document row is deleted? Look for orphaned files after failures and
for `thumbnail_path` handling (prior P1-14 nulled it on every processed document).

**Sharing and export.** `DocumentDetailView` share path: does the user get the decrypted
original or the encrypted blob (prior P1-10)? Does any export include PHI the user did not
intend (coordinate with WS-07)? Does "Export PDF report" produce real pages (prior P1-11)?

**Parsing correctness — this is where silent harm lives.** A mis-parsed lab value shown
as fact is worse than a failed import:
1. Unit handling: mg/dL vs mmol/L, and whether a value is ever converted or compared
   across units without conversion.
2. Reference ranges: parsed from the document or hardcoded? Sex/age-specific ranges?
   What happens when the document's range disagrees with the app's?
3. Decimal separators, thousands separators, `<0.5` / `>100` style results, negative
   values, and values the parser can't type — are they dropped, rounded, or stored wrong?
4. Date parsing: collection date vs report date vs import date; locale and timezone
   handling; two-digit years.
5. Low-confidence results: is there a review queue, and does it survive concurrent
   imports and app restart? (Prior P1-13: single in-memory slot.)
6. Is there any path where an extracted value is written into the health record without
   user confirmation? If so, say what the user sees.

**Progress and cancellation.** Does reported progress correspond to real work? Does
pause/clear restart work silently (prior P1-8)? Is cancellation propagated into OCR and
the model call, or only into the UI?

## Output

Plan §1.6 contract, plus:
- a **status transition table** (from → to → written at file:line → guard),
- an **input robustness table** (input → observed behaviour → file:line → severity).
