# MLX KV Cache Debugging Guide

**Last Updated**: 2025-12-20
**Status**: CRITICAL ISSUE - KV cache broadcast shape error on second conversation turn

---

## The Problem

MLX streaming conversations crash on the **second turn** with:
```
Fatal error: [broadcast_shapes] Shapes (1676,1676) and (1,8,1676,2700) cannot be broadcast.
```

**Observed Behavior** (BACKWARDS):
- **First turn**: Gets NO instruction formatting (plain 48-char question) → works
- **Second turn**: Gets FULL instruction formatting (INSTRUCTIONS/CONTEXT/QUESTION ~2700 chars) → crashes

**Expected Behavior**:
- **First turn**: Should get FULL instruction formatting for exception models like MedGemma
- **Second turn**: Should get ONLY user message (ChatSession maintains history)

**Root Cause**: The `requiresInstructionInjection` check is returning **false on first turn** and **true on second turn**, which is backwards.

---

## What We Fixed

### 1. Memory Management ([MLXClient.swift:183-199](HealthApp/HealthApp/Services/MLXClient.swift#L183-L199))
**Problem**: Double-loading models during session reset caused OOM crashes
**Fix**: Explicit unload sequence with 100ms delay
```swift
func resetSession() async throws {
    chatSession = nil  // Unload first
    try await Task.sleep(nanoseconds: 100_000_000)
    try await loadModel(modelId: modelId)  // Then reload
}
```

### 2. Performance ([MLXClient.swift:270-337](HealthApp/HealthApp/Services/MLXClient.swift#L270-L337))
**Problem**: UI updated on every token (100+/sec) causing CPU spikes
**Fix**: Time-based throttling to max 100ms intervals
```swift
var lastUpdateTime = Date()
let updateInterval: TimeInterval = 0.1

if timeSinceLastUpdate >= updateInterval {
    onUpdate(finalText)  // Only update every 100ms
}
```

### 3. Title Generation ([AIChatManager.swift:274-342](HealthApp/HealthApp/Managers/AIChatManager.swift#L274-L342))
**Problem**: Using ChatSession for title generation doubled memory usage
**Fix**: Heuristic-based title generation for MLX
```swift
if settingsManager.modelPreferences.aiProvider == .mlx {
    return generateHeuristicTitle(from: userMessage.content)
}
```

### 4. Model Name Detection ([AIChatManager.swift:395-405](HealthApp/HealthApp/Managers/AIChatManager.swift#L395-L405))
**Problem**: Using wrong model property (`chatModel` instead of `mlxModelId`)
**Fix**: Provider-specific switch statement
```swift
let currentModel: String
switch settingsManager.modelPreferences.aiProvider {
case .mlx:
    currentModel = settingsManager.modelPreferences.mlxModelId ?? ""
case .ollama, .openAICompatible:
    currentModel = settingsManager.modelPreferences.chatModel
case .bedrock:
    currentModel = settingsManager.modelPreferences.bedrockModel
}
```

### 5. Default Health Context ([AIChatManager.swift:19](HealthApp/HealthApp/Managers/AIChatManager.swift#L19))
**Problem**: Including blood tests by default was too much context
**Fix**: Changed default to personal info only
```swift
@Published var selectedHealthDataTypes: Set<HealthDataType> = [.personalInfo]
```

### 6. Configuration Persistence ([MLXSettingsView.swift:201-227](HealthApp/HealthApp/Views/MLXSettingsView.swift#L201-L227))
**Problem**: MLX generation settings reset on app restart
**Fix**: Save/load through SettingsManager
```swift
settingsManager.mlxGenerationConfig = generationConfig
settingsManager.saveSettings()
```

---

## Debug Logging Added

### Primary Debug Output ([AIChatManager.swift:409](HealthApp/HealthApp/Managers/AIChatManager.swift#L409))
```swift
print("🔍 AIChatManager: Provider=\(aiProvider), Model='\(currentModel)', isFirst=\(isFirstUserMessage), requiresInjection=\(requiresInjection)")
```

**What to look for**:
- `Provider` should be `mlx`
- `Model` should be something like `"medgemma-2b"` (NOT empty!)
- `isFirst` should be `true` for first message, `false` for subsequent
- `requiresInjection` should be `true` when Model contains "medgemma"

### Turn Type Logging ([AIChatManager.swift:437-440](HealthApp/HealthApp/Managers/AIChatManager.swift#L437-L440))
```swift
if isFirstUserMessage && requiresInjection {
    print("📝 AIChatManager: FIRST turn - sending formatted message (length: \(messageContent.count))")
} else {
    print("📝 AIChatManager: SUBSEQUENT turn - sending raw message (length: \(messageContent.count)), first 200 chars: '\(messageContent.prefix(200))'")
}
```

**What to look for**:
- First turn should say "FIRST turn - sending formatted message" with ~2000+ chars
- Subsequent turns should say "SUBSEQUENT turn - sending raw message" with ~50-200 chars
- The "first 200 chars" preview should show the actual user question, NOT "INSTRUCTIONS:"

### MLX Prompt Building ([MLXClient.swift:251-255](HealthApp/HealthApp/Services/MLXClient.swift#L251-L255))
```swift
if isFirstTurn {
    fullPrompt = buildPrompt(message: message, context: context, systemPrompt: systemPrompt)
    logger.debug("📋 First turn - including full context")
} else {
    fullPrompt = message
    logger.debug("📋 Subsequent turn - message only")
}
```

**What to look for**:
- First turn: "📋 First turn - including full context"
- Subsequent turns: "📋 Subsequent turn - message only"
- The actual prompt content in next log line (first 200 chars)

---

## How to Test

### 1. Enable Debug Logging
```bash
# In Xcode, run the app and check Console (⌘⇧C)
# Filter by: "🔍" or "📝" or "📋"
```

### 2. Test Sequence
1. Select MLX provider in settings
2. Load a MedGemma model (e.g., "medgemma-2b")
3. Start a new conversation
4. Send **first message**: "What are my blood test results?"
5. Wait for response
6. Send **second message**: "Tell me more"

### 3. Capture Console Output
**Look for these log lines in order**:

```
🔍 AIChatManager: Provider=mlx, Model='medgemma-2b', isFirst=true, requiresInjection=true
📝 AIChatManager: FIRST turn - sending formatted message (length: 2345)
📋 First turn - including full context
📋 Full prompt:
INSTRUCTIONS:
You are Dr. Smith...

CONTEXT:
Patient Health Information:
...

QUESTION:
What are my blood test results?
```

Then on second message:
```
🔍 AIChatManager: Provider=mlx, Model='medgemma-2b', isFirst=false, requiresInjection=false
📝 AIChatManager: SUBSEQUENT turn - sending raw message (length: 52), first 200 chars: 'Tell me more'
📋 Subsequent turn - message only
```

---

## The Backwards Problem

### Current Logs Show (WRONG):
```
# First turn - NO formatting (should have it!)
🔍 AIChatManager: Provider=mlx, Model='medgemma-2b', isFirst=true, requiresInjection=false  ← WRONG!
📝 AIChatManager: SUBSEQUENT turn - sending raw message (length: 48)  ← Says "SUBSEQUENT" on FIRST!
📋 Full prompt:
What are my blood test results?  ← Only 48 chars, missing INSTRUCTIONS

# Second turn - GETS formatting (shouldn't have it!)
🔍 AIChatManager: Provider=mlx, Model='medgemma-2b', isFirst=false, requiresInjection=true  ← WRONG!
📝 AIChatManager: FIRST turn - sending formatted message (length: 2345)  ← Says "FIRST" on SECOND!
📋 Full prompt:
INSTRUCTIONS:
You are Dr. Smith...  ← 2345 chars, causes KV cache shape mismatch
[CRASH: broadcast_shapes error]
```

### Why This Happens (Hypothesis)

One or more of these is likely wrong:

1. **Empty Model Name**: `mlxModelId` is `""` or `nil`
   - `requiresInstructionInjection("")` returns `false`
   - On first turn: no formatting
   - On second turn: some state change makes it return `true`

2. **Inverted First Message Check**: The `isFirstUserMessage` logic is backwards
   - Check [AIChatManager.swift:383-393](HealthApp/HealthApp/Managers/AIChatManager.swift#L383-L393)
   - Should be: `messages.filter { $0.role == .user }.isEmpty`

3. **State Persistence**: Something is cached between turns
   - The `currentModel` variable or `requiresInjection` result is stale
   - Check if evaluating `requiresInstructionInjection` twice gives different results

4. **Provider Mismatch**: The provider check is returning wrong value
   - Verify `settingsManager.modelPreferences.aiProvider == .mlx`

---

## Next Steps to Fix

### Step 1: Verify Model Name
Add this before line 409 in [AIChatManager.swift](HealthApp/HealthApp/Managers/AIChatManager.swift):
```swift
print("🔍 DEBUG: mlxModelId = '\(settingsManager.modelPreferences.mlxModelId ?? "nil")'")
print("🔍 DEBUG: aiProvider = \(settingsManager.modelPreferences.aiProvider)")
print("🔍 DEBUG: currentModel = '\(currentModel)'")
```

**Expected**: All three should show non-empty values on both turns

### Step 2: Verify Exception List
Add this before line 409:
```swift
let exceptionCheck = SystemPromptExceptionList.shared.requiresInstructionInjection(for: currentModel)
print("🔍 DEBUG: SystemPromptExceptionList.requiresInstructionInjection('\(currentModel)') = \(exceptionCheck)")
print("🔍 DEBUG: Available patterns: \(SystemPromptExceptionList.shared.getAllPatterns())")
```

**Expected**: Should return `true` for "medgemma-2b" on both turns

### Step 3: Verify First Message Detection
Add this before line 383:
```swift
let userMessages = messages.filter { $0.role == .user }
print("🔍 DEBUG: Total messages: \(messages.count), User messages: \(userMessages.count)")
print("🔍 DEBUG: isFirstUserMessage will be: \(userMessages.isEmpty)")
```

**Expected**:
- First turn: `User messages: 0`, `isFirstUserMessage = true`
- Second turn: `User messages: 1`, `isFirstUserMessage = false`

### Step 4: Check the Formatted Content
Add this after line 395:
```swift
if requiresInjection && isFirstUserMessage {
    let formatted = SystemPromptExceptionList.shared.formatFirstUserMessage(
        userMessage: content,
        systemPrompt: selectedDoctor?.systemPrompt,
        context: healthContext
    )
    print("🔍 DEBUG: Formatted content length: \(formatted.count)")
    print("🔍 DEBUG: First 200 chars: '\(String(formatted.prefix(200)))'")
}
```

**Expected**: Should only print on first turn, showing ~2000+ chars starting with "INSTRUCTIONS:"

---

## Files Modified

All changes are in commit `0fc80d1`:

1. [HealthApp/HealthApp/Services/MLXClient.swift](HealthApp/HealthApp/Services/MLXClient.swift)
   - Memory-safe session reset
   - First/subsequent turn prompt handling
   - Throttled UI updates
   - End-of-turn token detection
   - Disabled one-off generation

2. [HealthApp/HealthApp/Managers/AIChatManager.swift](HealthApp/HealthApp/Managers/AIChatManager.swift)
   - Provider-specific model name detection
   - Debug logging for troubleshooting
   - Heuristic title generation for MLX
   - Exception model handling refinement
   - Default context changed to personalInfo only

3. [HealthApp/HealthApp/Views/MLXSettingsView.swift](HealthApp/HealthApp/Views/MLXSettingsView.swift)
   - Configuration persistence
   - Model deletion functionality

---

## Known Working Components

✅ **Memory management**: No more OOM crashes
✅ **Performance**: UI updates throttled, no CPU spikes
✅ **Title generation**: Heuristic-based, no second model load
✅ **Model deletion**: iOS-compatible HuggingFace cache cleanup
✅ **Configuration**: Settings persist across app restarts
✅ **First turn works**: When it gets proper formatting (though currently doesn't)

---

## Critical Issue Still Unresolved

❌ **KV cache crash on second turn**
❌ **Backwards instruction injection logic**

The core problem is that `requiresInstructionInjection` is returning the opposite of what it should on each turn. Once we identify why (likely empty model name or inverted first message check), the fix should be straightforward.

**The debug logs added will help identify which hypothesis is correct.**

---

## References

- [SystemPromptExceptionList.swift](HealthApp/HealthApp/Utils/SystemPromptExceptionList.swift) - Exception model patterns
- [MLXModelRegistry.swift](HealthApp/HealthApp/Models/MLXModelRegistry.swift) - Available models
- [SettingsManager.swift](HealthApp/HealthApp/Managers/SettingsManager.swift) - Configuration storage
- [CLAUDE.md](CLAUDE.md) - Full project documentation

---

**When you resume**: Run the test sequence above and share the complete console output from both turns. The debug logs will show exactly which component is returning the wrong value.
