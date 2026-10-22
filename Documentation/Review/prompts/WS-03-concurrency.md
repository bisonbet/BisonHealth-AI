# WS-03 — Swift 6 concurrency & actor isolation

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-03-concurrency.md`**

The project is Swift 6 language mode with strict concurrency, but it still contains 27
`DispatchQueue` uses and 5 `@unchecked Sendable` declarations. Those are the places
where the compiler stopped helping and a human promised correctness instead. Audit the
promises.

## Scope

Whole app target, but start from these entry points:

```bash
grep -rn 'DispatchQueue' HealthApp/HealthApp --include='*.swift'
grep -rn '@unchecked Sendable' HealthApp/HealthApp --include='*.swift'
grep -rn 'nonisolated' HealthApp/HealthApp --include='*.swift'
grep -rn 'Task.detached\|Task {' HealthApp/HealthApp --include='*.swift' | wc -l
grep -rn 'AsyncStream\|AsyncThrowingStream\|continuation' HealthApp/HealthApp --include='*.swift'
grep -rn 'withCheckedContinuation\|withCheckedThrowingContinuation' HealthApp/HealthApp --include='*.swift'
grep -rn 'assumeIsolated\|MainActor.assumeIsolated' HealthApp/HealthApp --include='*.swift'
```

## What to examine

1. **Every `@unchecked Sendable`.** For each: what mutable state does the type hold, what
   synchronises it, and can two tasks reach it at once? An `@unchecked Sendable` class
   with a `var` and no lock is a data race the compiler was told to ignore. Report each
   one with its actual synchronisation story.

2. **Every `DispatchQueue`.** Classify: (a) legitimate (serial queue guarding a
   non-Sendable C API like SQLite), (b) redundant (hopping to main inside an already
   `@MainActor` type), (c) dangerous (a `.sync` that can deadlock, or a queue hop that
   breaks `Task` cancellation or priority). Look specifically for `.sync` called from a
   concurrent context and for queue hops inside async functions.

3. **Continuation discipline.** Every `withCheckedContinuation` must resume exactly once
   on every path including error and cancellation. A continuation resumed twice traps;
   one never resumed hangs the task forever. Trace each one's error paths. Pay attention
   to delegate-based wrappers (document scanning, HealthKit, PDF rendering) where the
   delegate may fire zero or twice.

4. **Cancellation.** Walk the long-running operations — AI streaming, document
   processing, MLX model download, OCR — and determine whether cancelling the `Task`
   actually stops the work and leaves consistent state. Prior review items P1-8 and P1-9
   were cancellation bugs; check whether the pattern recurs elsewhere. Look for
   `Task.isCancelled` checks inside loops and `try Task.checkCancellation()` at await
   boundaries.

5. **Streaming lifecycle.** `AIChatManager.swift` (~1,330 LOC) and the provider clients
   stream tokens. Check: can two streams run at once? What happens if the view
   disappears mid-stream? Is the accumulated text mutated from more than one isolation
   domain? Is the stream's buffer decoded as UTF-8 per chunk (a multi-byte character
   split across chunks corrupts — this was prior finding P1-3, verify the fix generalises
   to all three providers).

6. **`@MainActor` boundaries.** Managers are `@MainActor ObservableObject`. Find work
   that runs on the main actor but shouldn't: file I/O, decryption, OCR, JSON encoding of
   large payloads, SQLite queries. Each is a hitch or a beachball. Quantify where you
   can (payload sizes, loop counts).

7. **`@Published` mutation sites** reached from non-main contexts, and any
   `objectWillChange` sent off-main.

8. **Shared singletons** (`DatabaseManager.shared`, `SettingsManager`, log subsystem):
   initialisation races, lazy `static` with side effects, and whether `shared` is safe to
   touch before the first `MainActor` tick.

## Calibration

Do not report "uses DispatchQueue in a Swift 6 codebase" as a finding. Report the
specific race, deadlock, hang, or lost-cancellation it causes. If a `DispatchQueue` use
is correct, it belongs in a one-line table entry, not in the findings list.

## Output

Plan §1.6 contract, plus an **Isolation inventory** table before the findings:

| Site | Kind | Guarded by | Verdict (ok / suspect / defect) |
|---|---|---|---|
