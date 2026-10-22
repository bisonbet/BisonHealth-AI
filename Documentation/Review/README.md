# Beta & App Store review — how to run it

Start here: [`BETA-RELEASE-REVIEW-PLAN.md`](BETA-RELEASE-REVIEW-PLAN.md).

```
BETA-RELEASE-REVIEW-PLAN.md   the contract: repo facts, rules of engagement, severity
                              rubric, output format, workstream table, exit criteria
TRACKER.md                    the live worklist (empty until WS-17 triage runs)
prompts/WS-NN-*.md            18 standalone agent briefs
prompts/FIX-AGENT-PROTOCOL.md Phase 5: how a fix agent works and verifies
findings/                     agent output lands here, one file per workstream
```

## Dispatching a workstream

One line is enough — the prompt files are self-contained:

> Read `Documentation/Review/BETA-RELEASE-REVIEW-PLAN.md` sections 0 and 1, then execute
> `Documentation/Review/prompts/WS-05-document-pipeline.md` exactly. Write your output to
> the path that prompt specifies and nothing else. Do not modify any source file.

For a weak or cheap model, add:

> Follow the prompt literally, step by step, in order. Do not add steps. If a step cannot
> be completed, write that in `Scope not covered` rather than substituting your own
> approach. Every finding needs file:line and quoted code — if you cannot provide both,
> do not report it.

## Order

```
WS-00                                  ← first, alone (establishes the baseline)
WS-01 WS-02 WS-03 WS-07                ← correctness and safety core
WS-04 WS-05 WS-06 WS-08
WS-09 WS-10 WS-11 WS-12
WS-13 WS-14 WS-15 WS-16
WS-17                                  ← last, needs every findings file
```

Phases 1–3 are read-only and independent: run as many concurrently as your budget and
your own reading capacity allow. If the App Store date is the binding constraint, run
WS-13 and WS-14 early — they surface work that needs Apple-side lead time (app record,
certificates, screenshots, privacy answers).

## Model tiering

| Tier | Workstreams | Why |
|---|---|---|
| strong | 01, 02, 03, 04, 05, 06, 07, 17 | tracing async control flow and data lifetimes across files; a weak model produces confident nonsense here |
| mid | 08, 09, 11, 12, 13, 14, 15 | structured work that still needs judgment about user impact |
| cheap | 00, 10, 16 | mechanical, checklist- and grep-driven |

## The two failure modes to watch for

1. **Invented findings.** Mitigated by the evidence rules in plan §1.2 and by WS-17 step 3,
   which re-verifies every P0/P1 against the source before it reaches the tracker. Do not
   skip WS-17, and do not run it on a cheap model.
2. **Undifferentiated output.** Mitigated by the 15-finding cap per workstream and the
   severity rubric. If a report comes back with everything marked P0, send it back.

## Scope boundary

Reviewers never edit code. Fixes happen in Phase 5 under
[`prompts/FIX-AGENT-PROTOCOL.md`](prompts/FIX-AGENT-PROTOCOL.md), one work item per
branch, one owner per file, verified with real build and test output.
