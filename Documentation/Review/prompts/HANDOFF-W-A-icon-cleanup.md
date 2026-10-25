# W-A (remainder) — Delete the unused second app-icon set

**Finding:** WS-13-12 / WS-14-07, leftover · **Severity:** P3 · **Effort:** S (minutes)
**Files you own:** `HealthApp/HealthApp/Assets.xcassets/AppIcon-Doctor-Dark.appiconset/`,
possibly `HealthApp/HealthApp.xcodeproj/project.pbxproj`

Read `Documentation/Review/prompts/FIX-AGENT-PROTOCOL.md` first.

---

## What is wrong

`AppIcon-Doctor-Dark.appiconset` is a complete second app-icon set that nothing uses.
Verified:

- `ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-BisonHealthAI-Pro"` in both build
  configurations — that is the icon the app ships.
- `grep -c 'AppIcon-Doctor-Dark' HealthApp/HealthApp.xcodeproj/project.pbxproj` → **0**.
- No Swift file references it either.

Its 1024 px icon is also RGBA. That does not matter while it is unused — ITMS-90717 applies to
the app's actual icon, and the shipping one was converted to opaque RGB in commit `9f3ef1c4` —
but it is one more thing that looks like a submission risk to the next person who greps for it.

## What "done" looks like

- The `.appiconset` directory is gone.
- `xcodebuild` still builds for iPhone and iPad, and the app's icon is unchanged.
- No orphaned reference left anywhere. Check `project.pbxproj` and the asset catalog's
  `Contents.json` after deleting, not just before.

## Traps

- **Xcode asset catalogs are directories, and the catalog has its own `Contents.json`.** Make
  sure the catalog is still valid after the directory is removed; a dangling entry can fail
  the asset-compilation step rather than the Swift build, so look at the full build output and
  not just the exit status.
- **Do not touch `AppIcon-BisonHealthAI-Pro.appiconset`.** That is the shipping icon, and its
  1024 was deliberately re-encoded as opaque RGB with the visible pixels proved byte-identical.
  Re-encoding it again risks undoing that for no reason.
- **There is a third 1024 PNG**, `BisonHealthAI_ProIcon_1024.imageset`, which is an *imageset*
  rather than an appiconset — it may be used in UI (a splash or about screen). Check before
  assuming it is also dead. This item is only the appiconset.

## Verification expected of you

1. iPhone and iPad builds.
2. Confirm the built app still carries an icon: find the `.app` in DerivedData and check for
   the `AppIcon*` PNGs at its root.
3. Full suite + lint at the baseline, per the protocol. No tests should be affected; if any
   are, stop and report rather than adjusting them.

This one needs no negative check — there is no behaviour to regress, and the compiler plus the
icon check in the built product is the whole verification.
