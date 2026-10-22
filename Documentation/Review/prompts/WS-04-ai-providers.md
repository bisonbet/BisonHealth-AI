# WS-04 — AI provider layer & network robustness

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-04-ai-providers.md`**

Three providers, one interface. A beta tester will configure at most one of them, badly,
on a flaky network. Your job is to make sure every failure mode produces a message they
can act on instead of a spinner that never stops.

## Scope

- `HealthApp/HealthApp/Services/BedrockClient.swift` (~1,145 LOC)
- `HealthApp/HealthApp/Services/OpenAICompatibleClient.swift` (~1,240 LOC)
- `HealthApp/HealthApp/MLXOnDeviceLLM/MLXOnDeviceClient.swift` (~1,140 LOC)
- `HealthApp/HealthApp/Networking/` (2 files, ~445 LOC)
- `HealthApp/HealthApp/Managers/AIChatManager.swift` (~1,330 LOC) — the consumer
- `HealthApp/HealthApp/Views/AWSBedrockSettingsView.swift`,
  `OpenAICompatibleSettingsView.swift`, `OnDeviceLLMSettingsView.swift`,
  `ConnectionStatusBanner.swift`, `OfflineIndicatorView.swift`

## What to examine

1. **Interface conformance.** `AIProviderInterface` is `sendMessage` + `testConnection`.
   Do all three clients behave the same way for: empty response, HTTP error, malformed
   JSON, mid-stream disconnect, token limit exceeded, auth failure, and cancellation?
   Build a behaviour matrix. Divergence here is why "it works with Bedrock but not with
   Ollama" bugs happen.

2. **Timeouts.** Every request needs one, and it must be long enough for a slow local
   model (a 27B model on first token can take 30s+) and short enough that a dead endpoint
   doesn't hang forever. Find the actual values. A missing timeout on a streaming
   connection is a P1.

3. **Retries.** Is anything retried? If yes: is it idempotent, is there backoff, and is
   a retry on a *paid* cloud provider charged three times for one user action? Prior
   finding P1-6 was exactly this shape (3 retries, paid cloud passes). Check retries
   cannot fire on non-transient errors (400, 401, 422).

4. **Error surfacing.** Trace an error from each client up to the UI. Does the user see
   the provider's actual message, a generic "something went wrong", or nothing? Check the
   global error alert's actions actually do something (prior P1-4 was a no-op Retry).
   Check that an error ends the "typing" state — a stuck typing indicator reads as a hang.

5. **Endpoint validation and ATS.** `Info.plist` allows cleartext only to private /
   link-local / `.local` / unqualified hosts, and `OpenAICompatibleEndpointValidator` is
   said to enforce the same rule in-app. Verify the validator's rule actually matches the
   ATS exception (including IPv6 link-local, `127.0.0.1`, and hostnames that resolve to
   public IPs), and that a user cannot be talked into sending PHI in cleartext to a
   public host. Also check what happens on redirect — a `.local` endpoint 302-ing to a
   public HTTP URL.

6. **Credentials.** AWS keys in Keychain: accessibility class, whether they are ever
   logged, whether `testConnection` echoes them in an error, and what happens when they
   are rotated or revoked mid-session. Same for any API key on the OpenAI-compatible
   path. Verify no key material reaches `UserDefaults` or any log.

7. **Context assembly.** What health data is put into the prompt, and does it respect the
   user's privacy toggles? Prior P1-5 was opt-outs reverting to "include everything" —
   verify the toggle is honoured on *every* send path, including retries, regenerate,
   appointment prep, and title generation. Check context size limits: a user with 200 lab
   results must not silently blow the window or get truncated mid-record in a way that
   makes the model read the wrong value.

8. **Prompt-injection posture.** Health documents are attacker-influenced in the general
   case (a PDF someone emails the user). `CLAUDE.md` says `compactChatRules` tells the
   on-device model to treat patient data as facts, not instructions. Verify an equivalent
   guard exists on the Bedrock and OpenAI-compatible paths, and that document text is
   clearly delimited from instructions in the assembled prompt.

9. **Offline behaviour.** With no network: does the app detect it, does the on-device
   path still work, does the UI offer the right next step?

10. **Streaming cancellation and conversation switching** — coordinate with WS-03, but
    from the provider side: does cancelling leave a partial assistant message persisted,
    and is that message distinguishable from a complete one?

## Output

Plan §1.6 contract, plus the **provider behaviour matrix** (rows = failure modes,
columns = the three providers, cells = observed behaviour with file:line).
