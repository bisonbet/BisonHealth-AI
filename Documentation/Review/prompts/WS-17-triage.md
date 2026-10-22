# WS-17 — Triage, dedupe & fix sequencing

**Phase 4 · model tier: strong · runs last · output:
`Documentation/Review/findings/WS-17-triage.md` and an updated
`Documentation/Review/TRACKER.md`**

Sixteen workstreams have each produced up to 15 findings. Your job is to turn that into
one ordered worklist a human can approve and fix agents can execute without colliding.
You are the only agent allowed to overrule another agent's severity.

## Inputs

Every file in `Documentation/Review/findings/`. Read all of them, including the
machine-readable JSON blocks. If a workstream file is missing or marked `BLOCKED`, say so
and proceed with what exists — do not invent its findings.

## Steps

1. **Merge.** Build one table of all findings with their original IDs preserved.

2. **Dedupe.** The same defect will appear in several reports from different angles (a
   cancellation bug shows up in WS-03, WS-05, and WS-08). Merge them into one entry that
   keeps every reporter's evidence and lists the source IDs. Deduping is not deleting:
   never drop a finding without recording where it went.

3. **Verify the P0s and P1s yourself.** Do not take severity on faith. For every claimed
   P0 and P1, open the cited file:line and confirm the code says what the report says.
   Re-grade anything that doesn't hold up, and mark it `DOWNGRADED — evidence did not
   support` with your reasoning. A triage pass that rubber-stamps 40 P0s is worthless.
   This is the main defence against a weak agent's confident hallucination, so spend your
   effort here.

4. **Re-grade against the rubric** in plan §1.3, applying it uniformly — different
   reviewers will have calibrated differently. Expect to move items in both directions.

5. **Classify each finding** as:
   - `BETA-BLOCKER` — must be fixed before any outside tester gets a build;
   - `SUBMISSION-BLOCKER` — must be fixed before App Store submission;
   - `PRE-PUBLIC` — before the public release;
   - `BACKLOG` — after launch;
   - `ACCEPTED` — a real issue the project chooses to live with; must carry a one-line
     rationale for the human to approve or reject.

6. **Sequence the fixes.** Produce an ordered list. Order by: unblocks-other-work first,
   then data-safety, then crash/hang, then compliance deadlines, then everything else.
   Group fixes that touch the same file into a single work item so two agents never edit
   one file concurrently.

7. **Publish the file-ownership map.** For each work item: the files it will touch, the
   work items that must land first, and whether it needs a database migration (those
   serialise against each other absolutely — two migrations developed in parallel will
   both claim version 13).

8. **Size the effort.** S (< 1 hour), M (half a day), L (a day or more, or needs design).
   Total it per classification so the human can see what "beta-ready" actually costs.

9. **Flag the decisions only the owner can make.** Anything that is a product or business
   call — the iOS 26.0 floor, whether cloud providers ship in v1, how much the privacy
   policy promises, whether to delay for the missing migration tests — goes in a short
   **Decisions needed** section, each with the options and your recommendation.

10. **Write `TRACKER.md`.** Replace its contents with the merged, ordered worklist in the
    table format that file already defines, so it becomes the single live document for
    the fix phase.

## Output

`WS-17-triage.md` contains: the dedupe map (source IDs → merged ID), the re-grading
record (what you moved and why), the classification summary with effort totals, the
ordered fix list with the ownership map, and the **Decisions needed** section.

`TRACKER.md` contains the live worklist only — no analysis, no prose.

Finish with a direct answer to one question: **what is the shortest honest path to a
build that is safe to put in a beta tester's hands?** Name the work items, in order, with
the total effort. If the answer is "nothing blocks it", say that just as plainly.
