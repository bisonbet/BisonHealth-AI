# W-J — Migration tests from a v10 fixture

**Finding:** item 41 (WS-15-01) · **Severity:** P1, submission-blocking · **Effort:** L
**File you own:** `HealthApp/HealthAppTests/DatabaseTests.swift`

Read `Documentation/Review/prompts/FIX-AGENT-PROTOCOL.md` first. This file is only the
item-specific part.

---

## What is wrong

`DatabaseMigrationTests` exists and is good, but **every fixture it builds starts at v11 or
later**. Verified: the `INSERT INTO database_version` lines are at `DatabaseTests.swift:185`
(v11), `:223` (v12), `:301` and `:342` (both v13). There is no v10 fixture.

That matters because the **v11 step is the most destructive migration in the project** and has
therefore never executed in a test. From `DatabaseManager.swift:582-592`, migrating to v11:

- adds `included_personal_info_categories` to `chat_conversations`;
- calls `encryptDocumentPHIColumns(db:)`, which rewrites `file_name`, `notes`,
  `provider_name` and `extracted_text` on **every** document row from plaintext to AES-GCM
  ciphertext;
- calls `encryptChatTitles(db:)`, which does the same to every conversation title.

An in-place rewrite of every PHI column in the database, and nothing has ever run it against
a fixture. WS-15 also proved by mutation that **no-op'ing this entire step leaves all tests
green** — it was one of nine regressions it injected with no failure.

## What "done" looks like

- A v10 fixture, built the same way the existing ones are: let `DatabaseManager` create the
  real current schema, then wind the file back. That is the project's established pattern and
  it keeps the fixture honest — it is the shipping schema, not a hand-copied approximation.
  See the comment at `DatabaseTests.swift:65-79` for why.
- Data written through the app's own API before the wind-back, so the rows are what a user
  would actually have. The existing tests do this with `saveMedicalDocument`.
- Assertions that after opening, the v11 step **actually ran**: the stored column is no longer
  readable plaintext *and* the app reads the original value back. Asserting only the second
  half would pass if the migration did nothing.
- The chain runs: a v10 fixture should migrate all the way to `DatabaseManager.currentDatabaseVersion`
  (14 today). Assert against that constant, never a literal — a test hardcoding `13` went
  stale the day the version moved.
- Per WS-17, also cover **migration-backup deletion**. `resetDatabase()` calls
  `deleteMigrationBackups()`, and those backups hold pre-encryption plaintext PHI, so a reset
  that leaves them behind is a privacy failure. Nothing tests it.
- An **idempotency case per version**, as `CLAUDE.md` now requires: running the step twice must
  not double-encrypt and strand the data. `testTheTagsMigrationIsSafeToRunTwice` is the model.

## Traps

- **The test target does not link SQLite.swift.** The existing migration tests use raw
  `import SQLite3` with hand-rolled `execute` / `scalar` / `textScalar` helpers at
  `DatabaseTests.swift:99-150`. Use those; do not add a dependency.
- **Winding back v11 is harder than winding back v12-v14.** v12 drops a column, v13 adds a
  table, v14 rewrites one column — all easy to reverse. v11 encrypted several columns, so a
  genuine v10 fixture needs those columns written back as *plaintext*. You will have to write
  plaintext values in directly with `execute`, because the app's API encrypts on write. Make
  sure what you write is what v10 would really have held.
- **`encryptDocumentPHIColumns` must be idempotent or the fixture lies.** Check how it decides
  what to encrypt before you assume running it on a half-migrated row is safe.
- **Do not change `DatabaseManager`.** This item is tests only. If you find a real bug in a
  migration step, report it; do not fix it here — a migration change needs its own version
  and its own review.

## Verification expected of you

1. Full suite + lint at the baseline, per the protocol.
2. **The negative check is the whole point of this item.** For each migration step you now
   cover, no-op that step in `DatabaseManager` and confirm your new test goes red. WS-15
   showed nine regressions leaving the suite green; a migration test that passes against a
   disabled migration is worse than none, because it licenses the belief that the path is
   covered. Restore the step with a separate command — a long test run that times out
   mid-revert has stranded source in this repo before.
3. Report which steps you could *not* cover and why, rather than quietly covering four of five.

## Scope note

W-K (test hygiene: deleting the tests that cannot fail) also edits `DatabaseTests.swift`.
**Do not run both at once** — WS-17 sequenced W-K after W-J for exactly this reason.
