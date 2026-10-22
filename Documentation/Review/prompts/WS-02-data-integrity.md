# WS-02 — Data integrity, migrations & encryption at rest

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-02-data-integrity.md`**

This is the workstream where a mistake costs a beta tester their health records
permanently. Treat data loss as the primary risk and crashes as secondary.

## Scope

- `HealthApp/HealthApp/Database/` (8 files, ~3,150 LOC) — `DatabaseManager.swift` and the
  `+HealthData`, `+Documents`, `+Chat`, `+MedicalDocuments`, `+AppSettings` extensions.
- Any encryption/key-management helper under `HealthApp/HealthApp/Utils/`.
- `HealthApp/HealthApp/Models/` only where persistence/`Codable` shape matters.

## What to examine

**Migrations (highest priority).** The schema is at version 12.
1. Read every migration case and build the full version→version path table.
2. For each step, ask: is it idempotent if it half-ran and the app was killed? Is it
   wrapped in a transaction? Does a failure mid-migration leave a database that can
   neither be read nor re-migrated?
3. Check the fresh-install path builds exactly the same schema a migrated v1→v12
   database ends with. A divergence here produces bugs that only appear for upgraders —
   diff the `create` statements against the accumulated `addColumn`/`alter` calls
   column by column.
4. Check downgrade handling: `CLAUDE.md` says opening a newer DB throws
   `DatabaseError.incompatibleVersion`, recorded in `initializationError`, surfacing
   `DatabaseUnavailableView`. Verify that is what the code does, that it cannot crash,
   and that the user has a way out that isn't "delete the app".
5. Verify the version row is written **after** the migration succeeds, not before.
6. Is there a backup before migration? `CLAUDE.md` mentions
   `health_data.sqlite.backup.[timestamp]`. Confirm it is actually created, that it is
   encrypted to the same standard as the live DB, and that it is pruned (an unbounded
   backup set on a phone is a disk-space bug).

**Encryption at rest.**
7. Which tables/columns are encrypted and which are plaintext? Build the table. The
   prior review (P1-12) flagged the documents table as plaintext PHI while siblings
   encrypt — determine the state today.
8. Key management: where does the key come from, where is it stored (Keychain
   accessibility class matters — `WhenUnlocked` vs `AfterFirstUnlock` vs `Always`), what
   happens on device restore or a new device, and is the key ever logged or written to
   `UserDefaults`?
9. Is the SQLite file excluded from backups appropriately, and is the WAL/journal file
   covered by the same protection as the main DB? An encrypted-blob scheme still leaks
   via `-wal` and `-shm` files if the blobs are decrypted into temp storage.
10. Data-protection class on the file itself (`FileProtectionType`).

**Integrity and concurrency.**
11. Is there a single writer, or can two tasks write concurrently? Look for the SQLite
    connection's thread/queue discipline and whether `busyTimeout`/WAL is configured.
12. Foreign keys / orphan rows: deleting a conversation, document, or health record —
    does the dependent data go with it, or orphan? Check both directions.
13. Decode failures: if a stored blob can't be decoded into today's model (field added,
    enum case removed), does the app drop the row, crash, or surface an error? Enum
    `RawRepresentable` decoding of removed cases is the classic trap here.

## Verification you can actually run

You may create a scratch database under the scratchpad directory and exercise the
migration path against it if that is feasible without editing app code. If you do,
report the commands. Do not modify anything in the repo.

## Output

Plan §1.6 contract. Include two tables ahead of the findings:
- **Schema map**: table → columns → encrypted? → contains PHI?
- **Migration path**: version → changes → transactional? → tested by?
