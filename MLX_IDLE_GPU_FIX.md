# MLX Idle GPU/CPU Usage Fix

## Problem Identified

After loading an MLX model for the first time, the app exhibited:
1. **High idle CPU usage** (90-130%) across all panels, not just AI chat
2. **High GPU energy usage** (50%+ of total) even when idle on Settings page
3. **Degrading performance** on subsequent messages (lower tokens/second)
4. **Issue persists until app restart**
5. **Model stays loaded when switching to other AI providers**

## Root Cause

The MLX model (~2GB) stays loaded on GPU indefinitely after first use, with:
- **4GB GPU cache** allocated and actively managed by Metal framework
- **No cleanup mechanism** when idle - cache only cleared during generation or app backgrounding
- **Continuous GPU memory management** by the Metal framework causes high CPU/GPU usage
- **Model not unloaded when switching to Ollama/Bedrock/OpenAI**

## Fixes Applied

### 1. Two-Stage Automatic Cleanup ([MLXClient.swift:203-258](HealthApp/HealthApp/Services/MLXClient.swift:203))

Added **progressive idle resource management** with two stages:

#### Stage 1: GPU Cache Cleanup (30 seconds)
```swift
- Tracks last activity time (model load, message generation)
- After 30 seconds of inactivity, clears GPU cache
- Keeps model loaded in memory for quick resumption
- Frees temporary GPU resources (KV cache, computation cache)
- You'll see: "🧹 MLX Stage 1: Cleaning GPU cache after 30s"
```

**Impact**: Reduces GPU power usage while keeping model ready for instant responses.

#### Stage 2: Full Model Unload (120 seconds)
```swift
- After 120 seconds (2 minutes) of total inactivity
- Completely unloads the model from GPU memory
- Frees all ~2GB GPU resources
- Next message will require 3-5 second model reload
- You'll see: "🗑️ MLX Stage 2: Unloading model after 120s"
```

**Impact**: Maximum power savings when truly idle, automatic reload when needed.

### 2. Automatic Unload on Provider Switch ([SettingsManager.swift:235-256](HealthApp/HealthApp/Managers/SettingsManager.swift:235))

Added **automatic MLX model unload** when switching AI providers:

```swift
- Observes changes to AI provider setting
- When switching FROM MLX to Ollama/Bedrock/OpenAI
- Immediately unloads MLX model and clears GPU cache
- You'll see: "🔄 AI Provider changed from MLX to [provider] - unloading MLX model"
```

**Impact**: No wasted GPU resources when using other AI providers.

### 3. Reduced GPU Cache Limit ([MLXClient.swift:44](HealthApp/HealthApp/Services/MLXClient.swift:44))

```swift
Before: 4GB GPU cache
After:  2GB GPU cache
```

**Rationale**: The model itself is ~2GB. The extra 2GB cache wasn't providing significant benefit but was causing Metal to continuously manage more memory.

**Impact**: Less GPU memory for Metal to manage = lower idle power usage.

### 4. Activity Tracking

Added `markActivity()` calls at key points:
- Model loading ([MLXClient.swift:372](HealthApp/HealthApp/Services/MLXClient.swift:372))
- Message generation start ([MLXClient.swift:626](HealthApp/HealthApp/Services/MLXClient.swift:626))
- After generation complete ([MLXClient.swift:840](HealthApp/HealthApp/Services/MLXClient.swift:840))

**Impact**: Resets both 30s and 120s timers, ensuring cleanup only happens when truly idle.

## Expected Results

### Before Fix
- **Idle CPU**: 90-130%
- **GPU Energy**: 50%+ continuous
- **Performance**: Degrades on subsequent messages
- **Idle on Settings**: Still high GPU usage
- **Switching providers**: MLX model stays loaded

### After Fix (Progressive)
- **0-30 seconds idle**: Normal GPU usage with model loaded
- **30-120 seconds idle**: GPU cache cleared, CPU drops to ~20%, GPU energy ~10%
- **120+ seconds idle**: Model fully unloaded, CPU <5%, GPU energy <2%
- **Performance**: Consistent across all messages
- **Switching providers**: MLX unloads immediately, GPU freed
- **Next message after 120s**: 3-5 second reload delay (acceptable tradeoff)

### What You'll See in Console

When running the app, you'll see these new log messages:

```
# When app becomes active
▶️ App became active - MLX streaming enabled

# Stage 1: After 30 seconds of inactivity
🧹 MLX Stage 1: Cleaning GPU cache after 30s of inactivity
📊 [Before Idle Cleanup] GPU Memory - Active: X.XMB, Cache: X.XMB, Peak: X.XMB
📊 [After Idle Cleanup] GPU Memory - Active: X.XMB, Cache: 0.0MB, Peak: X.XMB
✅ MLX Stage 1 complete - GPU cache cleared, model still loaded

# Stage 2: After 120 seconds of inactivity
🗑️ MLX Stage 2: Unloading model after 120s of inactivity
📊 [Before Model Unload] GPU Memory - Active: X.XMB, Cache: 0.0MB, Peak: X.XMB
🗑️ Unloading MLX model
📊 [After Model Unload] GPU Memory - Active: 0.0MB, Cache: 0.0MB, Peak: X.XMB
✅ MLX model unloaded - all GPU resources freed
✅ MLX Stage 2 complete - Model fully unloaded, GPU resources freed

# When switching AI providers (e.g., MLX → Ollama)
🔄 AI Provider changed from MLX to Ollama - unloading MLX model
🗑️ Unloading MLX model
📊 [After Model Unload] GPU Memory - Active: 0.0MB, Cache: 0.0MB, Peak: X.XMB
✅ MLX model unloaded - all GPU resources freed

# After sending a message (resets both timers)
📊 [After Generation] GPU Memory - Active: X.XMB, Cache: X.XMB, Peak: X.XMB
📊 [After Cache Clear] GPU Memory - Active: X.XMB, Cache: 0.0MB, Peak: X.XMB
```

## Testing Steps

### Test 1: Two-Stage Idle Cleanup
1. **Build and run** the updated app
2. **Load MLX model** - send your first message
3. **Monitor Activity Monitor**:
   - Filter for "HealthApp"
   - Watch CPU % and Energy Impact columns
4. **Wait 30 seconds** after message completes:
   - Check console for "🧹 MLX Stage 1" message
   - CPU should drop to ~20%, GPU energy ~10%
   - Model still loaded (next message is instant)
5. **Wait another 90 seconds** (120s total):
   - Check console for "🗑️ MLX Stage 2" message
   - CPU should drop to <5%, GPU energy <2%
   - Model fully unloaded
6. **Send another message**:
   - Should see ~3-5 second load time
   - Performance should match first message

### Test 2: Provider Switching
1. **With MLX model loaded**, send a test message
2. **Go to Settings** → AI Provider
3. **Switch to Ollama** (or Bedrock/OpenAI)
4. **Check console** for "🔄 AI Provider changed from MLX" message
5. **Check Activity Monitor**:
   - CPU/GPU should drop immediately
   - No waiting for 120 second timeout
6. **Switch back to MLX**:
   - Send a message
   - Model reloads (3-5 seconds)
   - Works normally

### Test 3: Activity Resets Timer
1. **Load MLX model** and send message
2. **Wait 25 seconds** (before Stage 1 trigger)
3. **Send another message**
4. **Timer resets** - no cleanup happens
5. **Wait 30 more seconds** - Stage 1 triggers
6. **Verify** progressive cleanup still works

## Performance Monitoring

### Check GPU Memory Stats

Add this to your testing workflow to see memory changes:

```swift
// In MLXClient.swift, the logMemoryStats function shows:
// - Active Memory: Currently in-use GPU memory
// - Cache Memory: Cached tensors/data (this gets cleared on idle)
// - Peak Memory: Maximum GPU memory used
```

### Activity Monitor Metrics

Track these values over time:
- **CPU %**: Should spike during generation, drop to <10% when idle
- **Energy Impact**: Should be "Low" when idle after cleanup
- **GPU Activity**: Check in Window → GPU History (if available)

## Troubleshooting

### If CPU/GPU still high after 30 seconds:

1. **Check console logs** - confirm you see the "🧹 MLX: Cleaning GPU cache" message
2. **Verify no active operations** - ensure no messages are being sent
3. **Check lifecycle state** - ensure app is in foreground (cleanup only runs when active)
4. **Force cleanup** - background the app (GPU.clearCache() runs immediately)

### If performance still degrades:

1. **Check token counts** - high conversation history might be causing issues
2. **Try new conversation** - reset the session completely
3. **Monitor memory logs** - look for growing cache/active memory
4. **Consider session reset** - the auto-reset logic may need tuning

### If idle cleanup is too aggressive:

You can adjust the cleanup delay in [MLXClient.swift:50](HealthApp/HealthApp/Services/MLXClient.swift:50):

```swift
private static let idleCleanupDelay: TimeInterval = 30.0  // Increase to 60.0 or 120.0
```

## Technical Details

### Why not unload the model completely?

- **Loading cost**: 3-5 seconds to reload ~2GB model from disk
- **User experience**: Immediate response when sending next message
- **Cache clearing**: Sufficient to reduce idle power usage

### Why 30 seconds?

- **Balance**: Long enough to not interfere with normal chat flow
- **Power savings**: Short enough to reduce battery drain
- **User perception**: Most users pause >30s between messages

### What gets cleared?

- **GPU.clearCache()** clears:
  - Temporary tensor operations
  - Cached computation results
  - KV cache from previous generation
- **Keeps loaded**:
  - Model weights (the ~2GB model itself)
  - Model architecture
  - Session state (until explicit reset)

## Related Changes

This fix works in conjunction with the SwiftUI rendering optimizations made to ChatDetailView:
- Reduced message filtering overhead
- Smarter scroll triggering
- Both contribute to lower overall CPU usage

## Monitoring Script

Save this as `monitor_mlx_gpu.sh` for continuous monitoring:

```bash
#!/bin/bash
echo "Monitoring HealthApp CPU/GPU usage..."
echo "Press Ctrl+C to stop"
echo ""

while true; do
    # Get CPU percentage
    cpu=$(ps aux | grep "HealthApp" | grep -v grep | awk '{print $3}' | head -1)

    # Get memory
    mem=$(ps aux | grep "HealthApp" | grep -v grep | awk '{print $4}' | head -1)

    # Print with timestamp
    timestamp=$(date '+%H:%M:%S')

    if [ ! -z "$cpu" ]; then
        echo "[$timestamp] CPU: ${cpu}% | MEM: ${mem}%"
    fi

    sleep 2
done
```

Run with:
```bash
chmod +x monitor_mlx_gpu.sh
./monitor_mlx_gpu.sh
```

## Known MLX Framework Limitations

**Important**: MLX has a fundamental memory management design that may prevent full memory release:

### Active Memory vs Cache Memory
- **Active Memory**: Model weights and KVCache - held in MLXArrays
- **Cache Memory**: Temporary buffers that can be recycled

Our `unloadModel()` implementation:
1. Synchronizes GPU stream (completes pending operations)
2. Sets cacheLimit to 0 (forces immediate deallocation)
3. Clears Swift references in autoreleasepool
4. Triple-synchronizes and clears cache
5. Resets peak memory counter

**However**, per [GitHub Issue #742](https://github.com/ml-explore/mlx/issues/742) and [Issue #724](https://github.com/ml-explore/mlx-examples/issues/724):
- "If I delete a reference to an mx.array that has been evaluated, there's no way to get the memory back"
- Memory goes to Metal's buffer pool for reuse, not returned to system
- This is by design for performance optimization

### What We Can Control
- ✅ Cache memory (cleared via `GPU.clearCache()`)
- ✅ Cache limit (set to 0 for immediate deallocation)
- ✅ GPU stream synchronization (ensures operations complete)

### What MLX Controls
- ⚠️ Active memory (model weights) - may persist in Metal allocator
- ⚠️ Metal buffer pool management
- ⚠️ When buffers are returned to system

### Workarounds if Memory Persists
1. **App restart** - Only guaranteed way to fully release Metal buffers
2. **Background the app** - iOS may reclaim memory under pressure
3. **Use smaller models** - Reduce baseline memory footprint
4. **Cloud providers** - Offload to Bedrock/OpenAI for resource-intensive queries

## Next Steps if Issues Persist

1. **Profile with Instruments**:
   - Product → Profile (Cmd+I)
   - Select "Time Profiler"
   - Look for hot paths in MLX/Metal calls

2. **Check Metal GPU Timeline**:
   - Use "Metal System Trace" template
   - Look for continuous GPU work when idle

3. **Consider alternative approaches**:
   - Unload model after longer idle period (5-10 minutes)
   - Reduce model size (use smaller quantized model)
   - Use cloud providers for resource-intensive queries

## Summary

This fix implements **aggressive resource management** for MLX with known limitations:

### Stage 1: Light Cleanup (30 seconds)
1. ✅ Clears GPU cache to reduce power usage
2. ✅ Keeps model loaded for instant responses
3. 📊 Expected: Reduced cache memory, stable active memory

### Stage 2: Full Unload (120 seconds)
1. ✅ Synchronizes GPU streams and clears all Swift references
2. ✅ Sets cacheLimit to 0 for immediate buffer deallocation
3. ✅ Cancels all pending tasks (streaming, cleanup)
4. ⚠️ Active memory may persist due to MLX/Metal framework design
5. 📊 Expected: Cache cleared, active memory release depends on MLX

### Provider Switching
1. ✅ Automatically unloads MLX when switching to Ollama/Bedrock/OpenAI
2. ✅ Immediate cleanup attempt (no waiting for timeout)
3. ⚠️ Memory release subject to MLX framework limitations

### Other Improvements
1. ✅ Reduced GPU cache from 4GB to 2GB
2. ✅ Activity tracking prevents cleanup during active use
3. ✅ Guards prevent scheduling cleanup when no model loaded
4. ✅ Triple GPU synchronization during unload
5. ✅ Autoreleasepool for immediate ARC deallocation

### Aggressive Unload Steps (v2)
```swift
1. Cancel all pending tasks (cleanup, streaming)
2. Synchronize GPU stream (complete pending ops)
3. Set cacheLimit to 0 (force immediate deallocation)
4. Clear references in autoreleasepool
5. Synchronize again
6. Clear GPU cache
7. Final synchronize
8. Restore cache limit (256MB)
9. Reset peak memory counter
```

**Expected results** (best case, dependent on MLX framework):
- **0-30s idle**: Normal (model active)
- **30-120s idle**: Cache cleared
- **120s+ idle**: All references cleared, cache at 0
- **Provider switch**: Immediate unload attempt

**Note**: Full memory release to system may not occur due to MLX/Metal memory pooling. See "Known MLX Framework Limitations" section above.
