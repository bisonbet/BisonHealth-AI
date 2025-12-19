# System Prompt Exception Models

## Overview

Some LLM models (like MedGemma) don't properly support system prompts. For these models, the doctor's instructions must be injected directly into the first user message using a structured format.

## How It Works

### Normal Models (Default Behavior)

For most models, the doctor's system prompt is sent as:
- **Ollama**: Proper system message role
- **Bedrock**: System prompt parameter
- **OpenAI-Compatible**: System message role

### Exception Models (Special Handling)

For models in the exception list:
1. **First User Message**: Formatted with structured sections:
   ```
   INSTRUCTIONS:
   <doctor's system prompt>

   CONTEXT:
   <health data context>

   QUESTION:
   <user's actual question>
   ```

2. **Subsequent Messages**: Sent normally (no re-injection of instructions)

## Current Exception List

### Default Patterns

- **`medgemma`** - Matches any model with "medgemma" in the name:
  - `medgemma-2b`
  - `google/medgemma`
  - `medgemma-instruct`
  - etc.

### Pattern Matching

The exception list uses **case-insensitive partial matching**:
- Pattern `"medgemma"` matches `"MedGemma-2B-Instruct"`
- Pattern `"gemma3"` would match `"gemma3-12b"` and `"Gemma3-Vision"`

## Managing the Exception List

### Programmatic Access

```swift
// Check if a model requires injection
let requiresInjection = SystemPromptExceptionList.shared
    .requiresInstructionInjection(for: "medgemma-2b")
// Returns: true

// Add a new pattern
SystemPromptExceptionList.shared.addPattern("llama3-medical")

// Remove a pattern
SystemPromptExceptionList.shared.removePattern("medgemma")

// Get all patterns
let patterns = SystemPromptExceptionList.shared.getAllPatterns()
// Returns: ["medgemma", "llama3-medical"]

// Reset to defaults
SystemPromptExceptionList.shared.resetToDefaults()
```

### Persistence

Exception patterns are automatically saved to `UserDefaults` under the key `SystemPromptExceptionPatterns`.

Changes persist across app launches.

## Adding New Patterns

To add a new model pattern to the exception list:

### Option 1: Add to Default List
Edit `SystemPromptExceptionList.swift`:
```swift
self.exceptionPatterns = [
    "medgemma",
    "your-new-pattern",  // Add here
]
```

### Option 2: Add at Runtime (Persists)
```swift
SystemPromptExceptionList.shared.addPattern("your-new-pattern")
```

### Option 3: Create UI (Future Enhancement)
A settings UI could be added to allow users to manage patterns visually:
- Add/remove patterns
- View current exception list
- Test if a model name matches

## Example Format

### For MedGemma with Orthopedic Specialist

**Input**:
- User Message: "What could be causing my knee pain?"
- Doctor: Orthopedic Specialist
- Health Context: Patient data...

**Formatted First Message**:
```
INSTRUCTIONS:
You are a board-certified orthopedic surgeon with over 20 years of clinical experience...
[Full orthopedic specialist system prompt]

CONTEXT:
Personal Health Info:
- Age: 45
- Height: 5'10"
- Weight: 180 lbs
[Health data...]

QUESTION:
What could be causing my knee pain?
```

## Technical Details

### Implementation Files

1. **`SystemPromptExceptionList.swift`** - Manages the exception list
2. **`AIChatManager.swift`** - Applies the formatting logic
   - Line ~353: Checks if model is in exception list
   - Line ~359: Formats first user message
   - Line ~383-396: Routes to streaming/non-streaming with appropriate context

### Detection Logic

```swift
// Check if this is the first user message
let isFirstUserMessage = conversation.messages
    .filter({ $0.role == .user }).count == 1

// Check if current model requires injection
let requiresInjection = SystemPromptExceptionList.shared
    .requiresInstructionInjection(for: currentModel)

// Apply formatting only on first message for exception models
if isFirstUserMessage && requiresInjection {
    messageContent = SystemPromptExceptionList.shared
        .formatFirstUserMessage(
            userMessage: content,
            systemPrompt: selectedDoctor?.systemPrompt,
            context: healthContext
        )
}
```

### Subsequent Messages

After the first message, exception models receive:
- **User messages**: Just the user's question (no re-injection)
- **Assistant messages**: Model's responses
- **Context**: Sent normally as system messages/context

The model is expected to remember the instructions from the first message.

## Benefits

1. **Better Model Compatibility**: Models like MedGemma that ignore system prompts now work correctly
2. **Configurable**: Easy to add new models without code changes
3. **Automatic**: App detects and handles formatting transparently
4. **Efficient**: Instructions only sent once (first message)
5. **Backward Compatible**: Normal models continue to work as before

## Testing

To test if a model is correctly handled:

1. Select a model with "medgemma" in its name
2. Start a new conversation with a doctor persona
3. Check console logs for:
   ```
   📝 AIChatManager: Model 'medgemma-2b' requires instruction injection - formatting first message
   📝 AIChatManager: Formatted message length: XXXX chars
   ```
4. Verify the model receives and follows the doctor's instructions

## Future Enhancements

- [ ] Settings UI for managing exception patterns
- [ ] Per-provider exception lists (Ollama vs Bedrock patterns might differ)
- [ ] Option to test format without sending (preview mode)
- [ ] Statistics on which models are being used with exceptions
- [ ] Automatic pattern suggestions based on model metadata

## References

- **MedGemma Documentation**: Recommends INSTRUCTIONS/CONTEXT/QUESTION format
- **Implementation Issue**: Models ignoring system prompts
- **Solution Pattern**: Instruction injection as documented by Google for MedGemma
