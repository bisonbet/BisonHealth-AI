# W-E — Cancel on-device generation when the app backgrounds

**Merged finding:** M-4 (WS-11-02 + WS-03-03) · **Severity:** P1 · **Effort:** M
**Files you own:** `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift`,
`HealthApp/HealthApp/HealthAppApp.swift`, `HealthApp/HealthApp/Managers/SettingsManager.swift`

Read `Documentation/Review/prompts/FIX-AGENT-PROTOCOL.md` first — it has the build commands,
the evidence standard and the lint rules. This file is only what is specific to this item.

---

## What is wrong

When the app goes to the background while an on-device reply is streaming, nothing stops the
generation, and the code that tries to free the model **waits behind it**.

Three separate facts, each verified at the line given:

1. **`isSuspendedForBackground` is never consulted by anything that generates.**
   `MLXOnDeviceClient.swift:131` declares it; the only reads are at `:666` and `:682`, both
   guards inside `suspendForBackground()` / `resumeAfterForeground()` that make those two
   methods idempotent. The token loop in `sendStreamingChatMessage` does not look at it, so
   setting it has no effect on work already running.

2. **The unload queues behind the generation.** `sendStreamingChatMessage` takes
   `MLXGPUGate.shared.acquire()` at `:283` and holds it for the whole reply via `defer`.
   `suspendForBackground()` at `:665` sets the flag and then also calls
   `await MLXGPUGate.shared.acquire()`, so it blocks until the reply finishes — which can be
   the full `maxTokens` budget (up to 4,096 tokens). The comment there says the model is
   given back "entirely" because a backgrounded app holding ~2.4 GB is the first thing the OS
   reclaims. That intent is correct; the implementation cannot deliver it while a reply runs.

3. **Nothing can cancel the generation even if it wanted to.** There is no retained task
   handle for the streaming send anywhere in the codebase — `grep` for `streamingTask`,
   `generationTask`, `currentSendTask` finds nothing. And `MLXGPUGate` (`:34-55`) parks
   waiters in `CheckedContinuation<Void, Never>` with no cancellation handling, so a waiting
   `acquire()` cannot be interrupted either.

**Consequence:** the app stays resident holding the model for as long as the reply takes, in
exactly the state the OS is most likely to kill. WS-11 and WS-03 both reported this; WS-17
declined to promote it beyond P1 because the *harmful* outcome — a jetsam kill or a Metal
"command buffer references deallocated object" abort — needs a device to confirm.

## What "done" looks like

- Generation observes cancellation and stops at a token boundary when the app backgrounds.
- `suspendForBackground()` does not wait for a running reply before unloading.
- A reply interrupted this way leaves the conversation in a sane state — the partial text is
  either kept deliberately or discarded deliberately, not left as an empty assistant bubble.
  `sendStreamingChatMessage` already has handling for an interrupted stream (it drops the
  cached `chatSession` so the next turn re-prefills); reuse that rather than inventing a path.
- `isSuspendedForBackground` is either genuinely consulted or removed. Do not leave a flag
  that reads as a safeguard and is not one.

## Traps, in the order you will hit them

- **The simulator compiles none of this.** `MLXOnDeviceClient.swift` wraps its load, generate
  and transfer bodies in `#if !targetEnvironment(simulator)`. Your change will not be
  compiled by a simulator build or reached by any test. Typecheck with the device build in
  the protocol, and say in your report that the behaviour is unverified at runtime.
- **Do not make `MLXGPUGate` cancellable by switching to `CheckedContinuation<Void, Error>`
  without thinking it through.** Several callers `defer { release() }` immediately after
  `acquire()`; a throwing acquire changes their control flow. If the gate needs cancellation,
  look at every `acquire()` call site first (there are several in this one file).
- **Tearing down while GPU work is in flight is the bug the gate exists to prevent.** The
  comment at `:669-672` is explicit: dropping a container or clearing the buffer pool while a
  command buffer is live aborts the process. A fix that unloads *without* waiting must first
  make the generation actually stop, not just stop being waited on.
- **Backgrounding is also how the download watchdog gets confused** — see
  `MLXModelDownloadManager.pauseForBackground()`. Do not change that path; it is a different
  item and already fixed.

## Verification expected of you

1. Device build (the only one that compiles this code).
2. Full suite + lint at the baseline, per the protocol.
3. A unit test of whatever decision rule you extract. You cannot test the MLX wiring, so put
   the logic that decides "should this turn stop now" in something testable, and say plainly
   in your report that the wiring itself is unverified.
4. **A negative check:** revert your fix and confirm your new test fails. This project has
   had six tests that passed for the wrong reason; the usual cause is a test whose expected
   value is derived from the same constant it asserts against.

## What needs the owner, not you

Confirming the harmful outcome needs a physical device: background the app mid-reply, see
whether it is killed or hangs. If the owner has already reported that result, it is in
`Documentation/Review/TRACKER.md` under "What W-C settled". If it is still marked awaiting,
treat the severity as unconfirmed and say so.
