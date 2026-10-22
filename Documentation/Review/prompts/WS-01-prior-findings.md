# WS-01 — Prior-findings regression verification

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-01-prior-findings.md`**

`PRE-BETA-REVIEW.md` at the repo root documents a deep review from 2026-08-30: 2 P0s,
15 P1s, and ~40 P2s, followed by a "Fix Status" section claiming all P0/P1 and 27 P2s
were fixed, then a fresh-eyes verification round. Since then the repo has had a dead-code
removal pass, a Docling removal (dropping the `raw_docling_output` column), and a
`TypingIndicatorView` restoration.

Your job: **verify the claims, and find the fixes that regressed.** This is the
highest-value workstream in the plan, because a fix that was removed by a later
refactor is invisible to a fresh reviewer.

## Method

For each P0 and P1 in `PRE-BETA-REVIEW.md`:

1. Read the finding and the claimed fix.
2. Locate the code the fix lives in today. The file or symbol may have been renamed or
   deleted by the dead-code/Docling passes — `git log -S'<symbol>' --oneline` and
   `git log --oneline -- <path>` will tell you what happened.
3. Classify it:
   - `HOLDS` — the fix is present and the defect cannot recur. Say what makes it
     impossible, not just that the code looks right.
   - `REGRESSED` — the guard is gone or has been bypassed. This is a finding, severity
     inherited from the original (a regressed P0 is a P0).
   - `PARTIAL` — fixed on the path the original described, still reachable by another path.
     Name the other path.
   - `UNVERIFIABLE` — the code no longer exists in a comparable form. Explain what
     replaced it and whether the new code has the same class of defect.
4. Pay special attention to these, which are the most refactor-fragile of the set:
   - P0-1 PDF page index crash during import
   - P0-2 PHI in durable plaintext logs in release builds
   - P1-1/1-2/1-3 streaming lifecycle, conversation switching mid-stream, UTF-8 chunk
     boundary corruption
   - P1-5 privacy opt-outs reverting to "include everything"
   - P1-8/1-9 cancellation propagation and documents stuck in `.processing`
   - P1-10 share handing out the encrypted file
   - P1-12 documents table storing PHI in plaintext while siblings encrypt
   - P1-13 review-needed lab values in a single in-memory slot
   - P1-14 `thumbnail_path` overwritten to NULL
   - P1-15 multi-file import processing only the first file

5. Then check the **Docling removal specifically**: commit `28fe453b` dropped the
   `raw_docling_output` column. Verify the migration that drops it is safe on an
   existing v11 database, that nothing still reads that column, and that the version
   bump landed. A dropped column on SQLite is a table rebuild in many cases — confirm
   which mechanism was used and whether data in sibling columns survives.

6. Check the **dead-code removal** (`4dfde676`, ~3k lines) for removed-but-needed code:
   `git show --stat 4dfde676` then spot-check anything that was a guard, validator, or
   error path rather than a view or helper. The `TypingIndicatorView` fix in `84e8c0f7`
   proves that pass removed at least one thing it shouldn't have — look for siblings.

## Constraints

- Do not re-report the items `PRE-BETA-REVIEW.md` lists as deliberately deferred unless
  you can show they are now worse than documented.
- Do not re-review the whole codebase. Other workstreams cover that. Stay on the prior
  findings and the two refactor commits.
- A `HOLDS` verdict needs the same evidence standard as a finding: file:line and the
  code that enforces it.

## Output

Plan §1.6 contract, plus a **Regression matrix** table before the findings:

| Prior ID | Title (short) | Claimed fix | Today | Evidence |
|---|---|---|---|---|

Set `Verdict` to a plain statement of how much of the prior review still holds.
