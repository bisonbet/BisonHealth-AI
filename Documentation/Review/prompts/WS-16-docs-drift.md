# WS-16 — Docs & plan drift

**Phase 3 · model tier: cheap · output: `Documentation/Review/findings/WS-16-docs-drift.md`**

Six root-level markdown files instruct humans and agents how to work on this repo. When
they drift from the code, every future agent inherits the error. This workstream makes
the docs true again, and checks the public-facing claims in `README.md` against what the
app does.

## Files in scope

`CLAUDE.md`, `AGENTS.md`, `AGENT_CODEBASE_INSTRUCTIONS.md`, `CONTRIBUTING.md`,
`README.md`, `PRE-BETA-REVIEW.md`, `.claude/CLAUDE.md`, `Personas-Prompts/README.md`.

## Method — verify every factual claim against the code

For each claim, record: claim → location in doc → actual value → verdict (true / stale /
wrong). Known drift to confirm and fix, plus whatever else you find:

1. `CLAUDE.md` "Quick Facts" says *"SQLite with CryptoKit encryption (current version:
   10)"*, while the Database Migrations section and the Quick Reference footer say 12.
   `DatabaseManager.currentDatabaseVersion` is the authority — check it and reconcile all
   three places.
2. `CLAUDE.md` migration example shows `currentDatabaseVersion = 11 // Was 10` — stale
   once the real version is 12. Update the example to the next real version.
3. `CLAUDE.md` build commands target `iPad Pro 11-inch (M5)` while its Testing section
   and `README.md` say `iPad Pro 11-inch (M4)`. Check which runtimes are actually
   installed (`xcrun simctl list devices available`) and make the docs name one thing.
4. `CLAUDE.md` claims a document-OCR stack of PDFKit + Vision via `NativeDocumentExtractor`
   and lists the manager/service tables. Verify every type named in those tables still
   exists (the dead-code and Docling removal passes deleted ~3k lines) and that no listed
   method name is gone.
5. `CLAUDE.md` says "Current project facts: Database version: 12" and
   "Last Updated: 2026-08-22" — a date that predates the last three commits. Refresh.
6. `README.md`: verify the architecture diagram, the supported health data types list, the
   configuration instructions, the roadmap, and especially §"Privacy & Security" and
   §"Personal Use Only — Not HIPAA Compliant". Every privacy sentence must be something
   WS-07 can defend. Flag any claim the code contradicts as a P1 — a false privacy claim
   in a public README is a trust and App Store problem, not a typo.
7. `AGENTS.md` §"Adding New Files to Xcode Project" says four places in `project.pbxproj`.
   Verify that is still accurate for this project format, since agents will follow it blind.
8. `CONTRIBUTING.md` and `AGENT_CODEBASE_INSTRUCTIONS.md`: check the commands, paths, and
   the Definition of Done still match `CLAUDE.md`. Where two docs state the same rule
   differently, say which should be the single source and which should point at it.
9. `Documentation/Archive/hipaa-positioning-webpage.html` — an archived HIPAA positioning
   page. Read it and confirm it makes no claim that contradicts the current "not HIPAA
   compliant" stance. If it does, flag it; an archived file still ships in the repo.
10. `PRE-BETA-REVIEW.md` is a point-in-time document now partly superseded by WS-01's
    verification. Propose how to close it out (a status header pointing at the new review,
    not a deletion — the history is useful).

## Also produce

A short **doc map**: which file is authoritative for what, so the next agent knows where
to look and the same fact stops living in four places. Note any rule that exists in only
one doc and should be in `CLAUDE.md` because agents read that first.

## Constraints

Do not edit the docs in this phase — report the exact replacement text for each drifted
claim so a Phase 5 agent can apply it mechanically. Keep findings factual; do not
rewrite prose you merely dislike.

## Output

Plan §1.6 contract, plus the **claim verification table** and the **doc map**. Severity:
a claim that misleads about privacy or data safety is P1; a wrong build command or stale
version number that will mislead an agent is P2; everything else P3.
