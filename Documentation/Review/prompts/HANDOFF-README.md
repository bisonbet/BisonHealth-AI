# Hand-off briefs

Each `HANDOFF-*.md` here is one work item, written to be given to an agent that has never
seen this repository. They all assume `FIX-AGENT-PROTOCOL.md` is read first — that holds the
build commands, the lint rules, the evidence standard and the Definition of Done, so the
briefs do not repeat them.

The ordering and file-ownership map these come from is §4 of
`../findings/WS-17-triage.md`. Current status is the top of `../TRACKER.md`.

## Ready to hand off

| Brief | Item | Effort | Notes |
|---|---|---|---|
| `HANDOFF-W-E-background-cancel.md` | W-E | M | Biggest of these. Touches MLX code that **no test can reach** and no simulator compiles. |
| `HANDOFF-W-J-migration-tests.md` | W-J | L | Tests only. Serialise with W-K — same file. |
| `HANDOFF-W-B-persist-failure-reason.md` | W-B rest | M | **Claims schema v15. Mutually exclusive with W-Q.** |
| `HANDOFF-W-A-icon-cleanup.md` | W-A rest | S | Minutes. Good first task for a new agent. |

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
