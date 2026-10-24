# Phase 5 — Fix agent protocol

**Model tier: match the finding (data/concurrency/migration fixes need a strong model) ·
one work item per agent · output: a branch plus a short report**

You are fixing exactly one work item from `Documentation/Review/TRACKER.md`. Read plan
§3 before you start. The review is over; your job is narrow and verifiable.

## Before you touch code

1. Read the work item and every finding merged into it.
2. Open each cited `file:line` and confirm the defect is still there. If it is not, stop,
   mark the item `ALREADY FIXED` in your report with evidence, and do nothing else.
3. Check the ownership map: if another agent holds one of your files, stop and say so.
4. Create the branch: `git checkout -b fix/ws-NN-NN-<slug>` from the current `main`.

## While fixing

- **Smallest change that fixes the defect.** No refactors, no renames, no reformatting, no
  "while I was in here". If the right fix requires restructuring, stop and write the design
  question instead of guessing.
- **Match the surrounding code**: comment density, naming, idiom. Read neighbouring
  functions first.
- **Project rules apply** (`CLAUDE.md`): `NavigationStack` not `NavigationView`,
  `@MainActor` on `ObservableObject`, async/await over completion handlers, no force
  unwraps, accessibility label/hint/identifier on every new control, `MARK:` sections,
  and iPhone **and** iPad support for any UI change.
- **Schema changes**: increment `currentDatabaseVersion`, add the migration case, and test
  fresh install *and* upgrade from the previous version. If the tracker says another item
  also needs a migration, coordinate — only one of you may claim the next version number.
- **New files** must be added to `project.pbxproj` by hand in all four places
  (`AGENTS.md` §"Adding New Files to Xcode Project"). Expect SourceKit errors until the
  next successful build; that is normal and not a reason to revert.
- **Add the regression test** the finding's `Verification` field specifies. A fix without a
  test that would have caught it is incomplete unless the tracker explicitly says
  "no test — UI-only" with a reason.

## Before claiming done

Run these and paste the real output into your report — not a summary, not a claim:

```bash
cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

```bash
cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.5' build
```

```bash
cd HealthApp && xcodebuild test -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

```bash
cd HealthApp && swiftlint lint --config .swiftlint.yml
```

`swiftlint` must be run from `HealthApp/` — that is where `.swiftlint.yml` lives, and from
the repository root it reports a dozen times the baseline because it finds no config.

**If your change touches `MLXOnDeviceLLM/`, a simulator build may prove nothing.** Those
files do compile in the simulator — their types, published state and pure helpers sit outside
the guards. What is `#if !targetEnvironment(simulator)` is the MLX imports and the bodies that
load a model, generate, and transfer bytes; the simulator builds stubs in their place. So an
error inside one of those bodies compiles clean and no test reaches it. Typecheck them with a
device build as well:

```bash
cd HealthApp && xcodebuild -project HealthApp.xcodeproj -scheme HealthApp \
  -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Nothing in those files can be *run* without a physical device, so put the decision rule of
any MLX fix in a plain value type that the simulator can unit-test, and say in your report
that the MLX-side wiring is unverified.

Then:

- Execute the finding's `Verification` steps and state the result.
- `git diff main...HEAD` — read it line by line. Remove anything that is not part of this
  fix: debug prints, commented-out code, stray whitespace changes.
- Apply the `CLAUDE.md` Definition of Done: delete code this change made unused, merge
  helpers this change duplicated, confirm no secrets or PHI landed in source, tests,
  fixtures, or logs.
- Do **not** commit to `main`. Do **not** push or open a PR unless the human asked.

## Your report

Short and factual:

```markdown
# Fix: <work item id> — <title>
- Branch: fix/ws-NN-NN-<slug>
- Findings addressed: WS-NN-NN (+ merged ids)
- Root cause: <one or two sentences>
- Change: <what you did, per file>
- Test added: <name, or "none — reason">
- Verification: <the finding's steps and their result>
- Build iPhone: PASS/FAIL · Build iPad: PASS/FAIL · Tests: n passed / n failed · Lint: clean?
- Deliberately not done: <anything in scope you left, and why>
- New findings discovered: <added to TRACKER.md as WS-NN-NN, not fixed here>
```

If anything failed, say so with the output. A truthful FAIL is useful; a fix reported as
done that doesn't build costs the next agent an hour and the human their trust in this
process.
