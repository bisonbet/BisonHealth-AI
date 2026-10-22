# WS-12 — On-device model lifecycle (MLX)

**Phase 2 · model tier: mid · output: `Documentation/Review/findings/WS-12-mlx-lifecycle.md`**

The on-device path is the app's privacy story and its biggest operational liability:
multi-gigabyte downloads, memory gates, and a dependency on `ml-explore/mlx-swift-lm`.
It is also the part most likely to draw an App Store question about downloaded content.

## Scope

- `HealthApp/HealthApp/MLXOnDeviceLLM/` (4 files, ~2,780 LOC):
  `MLXModelDownloadManager.swift` (~1,235), `MLXOnDeviceClient.swift` (~1,140),
  `MLXOnDeviceModels.swift`, and the fourth file
- `HealthApp/HealthApp/Views/OnDeviceLLMSettingsView.swift`
- `HealthApp/HealthApp/Views/StorageUsageView.swift`

## Download manager

1. **Resumability.** Kill the app mid-download, lose the network, background the app: does
   the download resume, restart, or leave a corrupt partial that is treated as complete?
   Verify whether `URLSession` background configuration is used, and if not, what happens
   when the user leaves the app during a 16 GB download.
2. **Integrity.** Is a checksum or size verified before a downloaded model is marked
   usable? A truncated shard that loads and produces garbage output is worse than a
   failed download. The MedGemma 27B option is described as three weight shards — check
   all shards are validated as a set.
3. **Disk space.** Is free space checked *before* starting, with headroom for the
   unpacked model? What happens when the device fills mid-download — is the partial
   cleaned up?
4. **Cellular.** Does a multi-gigabyte download start on cellular without consent? That
   is a real-world complaint and arguably a guideline issue.
5. **Concurrency.** Can two downloads start at once? Can the user delete a model that is
   loading or in use?
6. **Progress accuracy.** Does reported progress reflect bytes of the whole set, and does
   it reach 100% only when the model is actually usable?
7. **Eviction.** Is there a way to delete a model, and does it free everything (weights,
   tokenizer, caches, partials)? Does `StorageUsageView` agree with reality?

## Memory gate

8. Verify the ≥24 GB installed-memory gate for the 27B text-only model: that it reads
   *installed* physical memory, that it is restricted to the iOS-on-Mac runtime as
   documented, and that the UI does not offer the model on devices that cannot run it.
   Check the behaviour when the gate passes but the OS still kills the app — is the state
   recoverable, or does the app relaunch into the same fatal load?
9. Check smaller models' memory requirements are also gated, and that a jetsam kill
   mid-inference doesn't corrupt a conversation or leave a half-written message.

## Inference path

10. `compactChatRules` in `MLXOnDeviceClient.swift` appends operational rules to every
    on-device chat carrying a persona or health context, and is deliberately excluded
    from title generation. Verify: the rules are present on every such path, title
    generation really is an isolated instruction-free session, and the rules survive
    prompt truncation (if the context is trimmed from the top, a rule block appended at
    the top is the first thing lost — check which end is trimmed).
11. Token limits and context window per model: what happens when health context exceeds
    it? Silent truncation of patient data is a correctness and safety problem, not just a
    UX one.
12. Cancellation of an in-flight generation; generating while a download runs; switching
    models mid-conversation.
13. Determinism/sampling settings exposed to the user — any that can make the model
    produce empty output and look broken.

## App Store angle

14. Downloading model weights after install interacts with the review guidelines on
    downloaded content and on app completeness. Fetch the **current** App Review
    Guidelines (do not rely on memory — they change) and assess: does the app function
    meaningfully before any model is downloaded? Is the download disclosed? Is the
    reviewer going to be asked to wait on a 16 GB download to evaluate the app? Record
    what should go in the reviewer notes. Coordinate the conclusion with WS-13.
15. The model source (Hugging Face) is a third-party network call: confirm it is in
    WS-07's egress inventory and disclosed in the privacy policy.

## Output

Plan §1.6 contract, plus a **model inventory table** (model → size → shards → memory gate
→ device eligibility → verified how) and a **download state machine** diagram or table.
