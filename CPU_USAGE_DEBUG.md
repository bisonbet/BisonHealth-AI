# CPU Usage Diagnostic Guide

## Quick Checks

### 1. Check for Re-rendering Loop
Add this to `EnhancedMessageListView` in ChatDetailView.swift (around line 325):

```swift
var body: some View {
    let _ = print("🔄 MessageListView rendering - message count: \(messages.count)")
    ScrollViewReader { proxy in
        // ... rest of code
    }
}
```

If you see continuous "🔄 MessageListView rendering" messages when idle, you have a re-rendering loop.

### 2. Check Message Filtering
Replace line 329 in ChatDetailView.swift:
```swift
// Before (runs on every render)
ForEach(messages.filter { !$0.content.isEmpty }) { message in

// After (computed once)
ForEach(filteredMessages) { message in
```

Add a computed property:
```swift
private var filteredMessages: [ChatMessage] {
    messages.filter { !$0.content.isEmpty }
}
```

### 3. Profile in Instruments
Run with Instruments to see exactly what's using CPU:

```bash
# In Xcode: Product > Profile (Cmd+I)
# Select "Time Profiler"
# Run the app and let it idle for 30 seconds
# Look at the call tree to see what's consuming CPU
```

## Specific Files to Check

### ChatDetailView.swift
- **Line 328-364**: Message list rendering and onChange modifiers
- **Line 348-356**: `onChange(of: messages.count)` - triggers on any message count change
- **Line 367-646**: `EnhancedMessageBubbleView` - Markdown rendering happens here

### AIChatManager.swift
- **Line 78-108**: Network monitoring setup - check if this is firing continuously
- **Line 581-619**: Streaming debounce mechanism

### MLXClient.swift
- **Line 117-151**: Lifecycle observers - may be firing events even when idle

## Common Fixes

### Fix 1: Optimize Message Filtering
```swift
// In EnhancedMessageListView
struct EnhancedMessageListView: View {
    let messages: [ChatMessage]
    let isLoading: Bool
    let isIPad: Bool
    var chatManager: AIChatManager?
    var conversationId: UUID?

    // Add computed property
    private var visibleMessages: [ChatMessage] {
        messages.filter { !$0.content.isEmpty }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: isIPad ? 16 : 12) {
                    ForEach(visibleMessages) { message in  // Use computed property
                        EnhancedMessageBubbleView(...)
                            .equatable()
                            .id(message.id)
                    }
                    // ... rest of code
                }
            }
        }
    }
}
```

### Fix 2: Reduce onChange Sensitivity
```swift
// Change from messages.count to messages.last?.id
.onChange(of: messages.last?.id) {
    // Only triggers when a NEW message is added, not when existing messages change
    withAnimation(.easeOut(duration: 0.2)) {
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}
```

### Fix 3: Disable Debug Logging
Check if you're running a Debug build with excessive logging. Build for Release:

```bash
# In Xcode: Product > Scheme > Edit Scheme
# Set Run configuration to "Release" instead of "Debug"
```

### Fix 4: Limit Markdown Rendering
If you have a long conversation history, consider:
- Only rendering visible messages
- Simplifying markdown theme
- Caching rendered markdown

## Expected Results

After fixes:
- Idle CPU should be < 10%
- Only spike when actively scrolling or typing
- GPU usage from loaded MLX model is normal (0-5%)

## If Still High After Fixes

1. **Check for memory leaks**: Use Instruments > Leaks
2. **Check for retain cycles**: Look for `[weak self]` usage
3. **Profile GPU usage**: Use Instruments > Metal System Trace
4. **Check SwiftUI view updates**: Add `let _ = Self._printChanges()` in body

## Report Format

When reporting results, include:
```
- CPU usage before: X%
- CPU usage after: Y%
- Which fix was applied: [Fix #]
- Number of messages in current conversation: N
- Current panel: [Health Data / Documents / AI Chat / Settings]
- Build configuration: [Debug / Release]
```
