# WS-11 — Performance, memory & battery

**Phase 2 · model tier: mid · output: `Documentation/Review/findings/WS-11-performance.md`**

The app runs multi-gigabyte language models, OCRs PDFs, and decrypts a SQLite database,
on a battery. The deployment target is iOS 26.0, so the oldest supported hardware is
still recent — but the MLX path can exhaust memory on any device.

## What to measure

**1. Launch.** Time from tap to interactive, cold and warm, on iPhone and iPad. Break
down what happens before the first frame: database open, migration check, settings load,
HealthKit query, model metadata scan. Anything on the main thread in that window is a
finding. Report measured numbers, not impressions; if you cannot measure, say so and
reason from the code with explicit assumptions.

**2. Memory ceilings.** The app holds `com.apple.developer.kernel.increased-memory-limit`.
- What is the resident set at idle, after a document import, during a chat, and with a
  model loaded?
- `CLAUDE.md` notes a ~16 GB MedGemma 27B option gated to ≥24 GB *installed* physical
  memory, iOS-on-Mac only. Verify the gate reads installed memory (not available), that
  it cannot be bypassed in the UI, and what happens if the OS kills the app mid-load.
- Is there any `didReceiveMemoryWarning` equivalent? What is dropped under pressure?
- Can a model and a large PDF be resident at the same time? Estimate the peak.

**3. Document processing.** For a 50-page scanned PDF: peak memory, wall time, whether
pages are processed streaming or all held at once, and whether the UI stays responsive.
Look for whole-file `Data(contentsOf:)` reads of large documents, image decoding without
downsampling, and thumbnail generation at full resolution.

**4. Database access patterns.** Count queries per screen appearance. Look for N+1 reads
(one query per row), full-table decrypt-and-filter where SQL could filter, missing
indexes on columns used in `WHERE`/`ORDER BY`, and repeated decryption of the same blob
within one render pass. Check what `HealthTabView` and the document list do on appear.

**5. Chat performance.** With a 500-message conversation: load time, scroll smoothness,
and the per-token append cost during streaming. Check whether the full conversation is
re-encoded or re-rendered per token.

**6. Battery and thermals.** Any polling timer, repeating task, or animation that runs
when it shouldn't; model inference without thermal backoff; download manager behaviour on
cellular. Check whether background work is actually requested as background work or just
left to be suspended mid-operation.

**7. Disk.** Total footprint of app + models + documents + logs + DB backups. Does
anything grow without bound (logs, backups, temp files, failed-download partials)? Is
there a storage screen (`Views/StorageUsageView.swift`) and does it report the truth?

## How to measure

Prefer real numbers: build for the simulator, launch via the iOS Simulator tools, and use
`xcrun simctl` / `os_signpost` / Instruments where available. Simulator memory is not
device memory — say so when reporting, and mark device-only measurements as not performed
if you cannot run on hardware.

## Output

Plan §1.6 contract, plus a **measurements table** (scenario → metric → value → how
measured → device/simulator) and an explicit statement of which numbers are measured
versus estimated.
