# W-B (remainder) — Persist why a document failed

**Finding:** WS-08-02, second half · **Severity:** P2 · **Effort:** M
**Files you own:** `HealthApp/HealthApp/Database/DatabaseManager.swift`,
`DatabaseManager+Documents.swift`, `DatabaseManager+MedicalDocuments.swift`,
`HealthApp/HealthApp/Services/DocumentProcessor.swift`,
`HealthApp/HealthApp/Models/MedicalDocument.swift`, `CLAUDE.md`

Read `Documentation/Review/prompts/FIX-AGENT-PROTOCOL.md` first.

---

## ⚠️ Read this before anything else: you are claiming schema v15

This item needs a column on `documents`, so it takes **schema version 15**. So does **W-Q**
(the path-rewriting migration that renames legacy `<uuid>_<original name>` files).

**Only one of W-B and W-Q may be in progress at a time.** Two migrations developed in
parallel both claim v15, and merging them means renumbering one and re-testing both. Before
you start, confirm W-Q is not in flight. The moment you start, claim v15 in
`Documentation/Review/TRACKER.md`.

`CLAUDE.md` also requires that a version bump updates **three** places in that file — Quick
Facts, the Current Database Version line, and Current project facts — **in the same commit**.
That file has gone stale twice, both times because a bump changed the code and not the docs.

## What is already done

The first half shipped. `DocumentProcessor.failureReason(for:)` at `DocumentProcessor.swift:547`
composes the recorded error's description with its recovery suggestion, and both
`DocumentDetailView` and `DocumentListView` display it. So a failed import now explains
itself — on a fresh install it reads "No on-device vision model is downloaded… Go to Settings
> On-Device AI and download a Vision model."

## What is wrong with it

It is **session-scoped**. The reason lives in `DocumentProcessor.processingErrors`, which is
in memory, while `.failed` is persisted by `updateDocumentStatus`. So after a relaunch the
document still shows a red badge and the explanation is gone. `DocumentDetailView` falls back
to naming the most common cause, which is better than nothing but is a guess.

## What "done" looks like

- A column on `documents` holding a short failure reason, written at the same point
  `processing_status` becomes `.failed` — `DocumentProcessor.swift` around the
  `updateDocumentStatus(..., status: .failed)` call and the `processingErrors.append` beside it.
- `failureReason(for:)` prefers the in-memory record (freshest) and falls back to the stored
  one, so behaviour in-session is unchanged and a relaunch keeps the explanation.
- Cleared when the document is reprocessed and succeeds. A stale reason on a now-working
  document is its own bug.
- A v15 migration with an **idempotency case**, per `CLAUDE.md`.

## The thing to get right

**The reason must not become a new PHI leak.** Several of these error strings interpolate the
file name — `DocumentProcessingError.documentNotFound(let fileName)` and
`.noValuesExtracted(let fileName)` both do, at `DocumentProcessor.swift` in the
`errorDescription` switch. A file name is patient-identifying: that is precisely why
`file_name` is an encrypted column and why new imports are now stored on disk as `<uuid>.<ext>`.

So either store the reason **encrypted** like `notes` and `provider_name` (use
`encryptTextField` / `decryptTextField`), or store a filename-free form. WS-17 recommended
the latter — "persist a short filename-free reason". Encrypting is more consistent with the
rest of the table; decide, and say which you chose and why.

Also note `MedicalDocument.unreadableFields`: the full-row writers **refuse** to write a
record whose columns could not be read back (`DatabaseError.lossyWriteRefused`). If you add a
field, decide whether a failure to read *it* should block a whole-row write. It probably
should not — a corrupt failure message is not worth refusing to save a document over.

## Verification expected of you

1. iPhone + iPad builds, full suite + lint at the baseline, per the protocol.
2. A migration test in `DatabaseMigrationTests`, matching the existing pattern, including the
   twice-run case.
3. A test that the reason survives a reopen of the database — that is the entire point.
4. **A negative check:** revert the persistence and confirm the survival test fails.
5. If you store it encrypted, assert the stored bytes are **not** the readable string, the way
   `testUpgradingFromVersion13EncryptsTagsAndKeepsThemReadable` does. Asserting only that it
   reads back would pass on plaintext.
