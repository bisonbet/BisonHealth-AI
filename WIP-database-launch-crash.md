# WIP — Database launch crash (paused 2026-08-22)

Delete this file before merging.

## The bug that started this

The installed app died at launch on macOS. Cause, from the unified log:

```
HealthApp/DatabaseManager.swift:14: Fatal error: Failed to initialize DatabaseManager:
incompatibleVersion("Database version 10 is newer than app version 8. Please update the app.")
```

An older build (schema v8) was opening a container database a newer build had already
migrated to v10. `DatabaseManager` correctly refuses a newer-than-expected schema, but
`DatabaseManager.shared` turned that thrown error into `fatalError`, so a recoverable
condition became an unrecoverable launch crash with no on-screen explanation.

## What is done (committed on this branch)

- `Database/DatabaseManager.swift`
  - `shared` no longer traps. On failure it logs at `.critical` and returns a degraded
    instance built by `init(unavailable:)`, which records `initializationError` and
    leaves `db` nil. Every query in the `DatabaseManager+*` extensions already guards
    `db == nil` and throws `DatabaseError.connectionFailed`, so nothing reads the
    placeholder state.
  - `DatabaseError` gained `recoverySuggestion` for all cases.
- `Views/DatabaseUnavailableView.swift` (new, registered in `project.pbxproj`)
  - Full-screen explanation for database or secure file storage failures: cause, what to do,
    a reassurance that data is untouched, the raw error text, plus "Share Diagnostic Logs"
    and "Copy Details".
- `HealthAppApp.swift`
  - `body` checks database and secure file storage initialization errors before showing
    the app shell and presents `DatabaseUnavailableView` for either failure.
  - `syncHealthKitOnLaunch()` now returns early when either dependency is unavailable —
    without this, the Health permission sheet could appear on top of the error screen.
- `Managers/HealthDataManager.swift`
  - Automatic health-data loading is skipped when either startup dependency is unavailable,
    so the recovery screen does not start background reads against a degraded manager.
- `Utils/FileSystemManager.swift`
  - `shared` no longer traps. On failure it logs at `.critical` and returns a degraded
    instance with `initializationError`; storage operations fail with the structured
    initialization error instead of touching placeholder paths.
- `CLAUDE.md`: database version corrected 8 → 10, migration examples renumbered to 11,
  added a note that downgrades are refused rather than crashed.

## Verified

- Generic iOS build succeeds with signing disabled.
- Full `DatabaseTests` passes on a signed iPhone 17 Pro simulator running iOS 26.5
  (4 tests), and the test runner boots without the filesystem `EXC_BREAKPOINT`/`SIGTRAP`.
- Failure path reproduced end to end. Inserted a fake `database_version` row of 11 into
  the simulator's database, launched, and confirmed: no crash, process stays alive, the
  critical log line is written, and `DatabaseUnavailableView` renders with the real
  error text. The fake row was removed afterwards and row counts match the pre-test
  backup (health_data 8, documents 4, the rest 0).

## Where it stopped — pick up here

**The normal launch path shows a blank off-white screen on the iPhone 17 Pro simulator
and was never visually confirmed.**

Evidence it is a simulator HealthKit artifact rather than a regression:

- The app process stays alive and logs normally.
- The window is hosting `HKHealthPrivacyHostAuthorizationViewController` from
  `com.apple.HealthPrivacyService` — the Health authorization sheet, rendering empty.
  It first appeared after tapping "Don't Allow" during the failure-path test.
- `HealthAppApp.swift:258` logs "App launch: HealthKit sync failed (this is normal if
  not authorized): Authorization not determined" — pre-existing behavior, unchanged.
- The only normal-path code change is extracting `appShell`; the new HealthKit guard
  is a no-op when the database opens.

Suggested first steps tomorrow:

1. Erase the simulator (`xcrun simctl erase 21752144-444D-4F0D-9884-635463963193`) or
   use a different device, then launch and confirm the app shell renders. Erasing
   destroys the simulator's health database, so back it up first if the test data
   matters.
2. If it is still blank on a clean simulator, the `appShell` extraction is the suspect —
   revert just that hunk and compare.
3. Manually verify the normal launch path on a clean simulator and run the UI test suite.
4. Build and run on "My Mac (Designed for iPad)" — that is where the original crash
   happened, and it replaces the older TestFlight copy in the same container.

## Follow-up fixed in this PR

`Utils/FileSystemManager.swift:15` had the identical `fatalError` in its `shared`
initializer. It now follows the same degraded-startup pattern as the database, so a
filesystem initialization problem reaches the recovery screen instead of terminating
the process with `EXC_BREAKPOINT`/`SIGTRAP`.
