# Hand-off briefs

Each `HANDOFF-*.md` here is one work item, written to be given to an agent that has never
seen this repository. They all assume `FIX-AGENT-PROTOCOL.md` is read first — that holds the
build commands, the lint rules, the evidence standard and the Definition of Done, so the
briefs do not repeat them.

The ordering and file-ownership map these come from is §4 of
`../findings/WS-17-triage.md`. Current status is the top of `../TRACKER.md`.

## Handed off and implemented — 2026-10-25

All four were implemented in one branch. **None of them was compiled or tested**: the agent
ran in a Linux container with no Xcode and no SwiftLint, so the protocol's verification
commands were not executable. **They were run on the owner's Mac on 2026-10-26:** device
build ✅, `Fast` plan ✅ 368 tests / 0 failures, SwiftLint ✅ 5 — but only after fixing a
compile error in `DatabaseTests.swift:663` that had kept the whole test bundle from building,
so none of the tests below had ever run. Per-item notes are in `../TRACKER.md`.

| Brief | Item | Effort | Outcome |
|---|---|---|---|
| `HANDOFF-W-E-background-cancel.md` | W-E | M | Implemented. `MLXTurnInterruption` + token-loop check; `MLXGPUGate` unchanged. Typechecks for a device (2026-10-26); runtime behaviour still unverified — no simulator compiles it, no test reaches it. **Covers only the streaming path**, see `../TRACKER.md`. |
| `HANDOFF-W-J-migration-tests.md` | W-J | L | Implemented. v10 fixture, backup-deletion coverage. **Found that the v11 encryption helpers are not idempotent** — reported, not fixed (tests-only item). **W-K may now start.** |
| `HANDOFF-W-B-persist-failure-reason.md` | W-B rest | M | Implemented. **Took schema v15; W-Q is now v16.** Reason stored encrypted. |
| `HANDOFF-W-A-icon-cleanup.md` | W-A rest | S | Done. Directory deleted, no orphaned references. |

## Do not hand these off

**W-I's remainder — the Apple Distribution identity.** This is not agent work. It needs the
owner's Apple Developer account: the keychain has an Apple Development identity and no
distribution certificate, so no signed export can be produced at all. Until one succeeds,
`ExportOptions.plist`'s `method` value is unverified (`app-store` vs `app-store-connect` has
moved between Xcode versions). An agent can only guess here, and a guess that *looks* done is
worse than the current state, which is honestly labelled as unverified in the file itself.

**Anything in W-C's list of runtime checks.** Background mid-reply, one real Bedrock call, and
a keychain restore on a genuine device upgrade all need physical hardware and, for Bedrock,
the owner's AWS credentials.

## Two rules that have each cost real time here

**A simulator build proves nothing about `MLXOnDeviceLLM/`.** Those files compile, but the
bodies that load a model, generate and transfer bytes are inside
`#if !targetEnvironment(simulator)` and are replaced by stubs. Nothing in the test suite has
ever executed them. Typecheck with the `generic/platform=iOS` build in the protocol, and say
in your report that the runtime behaviour is unverified.

**Do the negative check, and distrust tests that pass it too easily.** Revert your fix and
confirm your new test goes red. Six tests written during this review passed for the wrong
reason, and the recurring cause is a test whose expected value is derived from the same
constant it asserts against — it cannot fail, whatever the code does. If reverting the fix
leaves your test green, the test is the problem.
