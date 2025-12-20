# MLX Integration - Quick Start

Quick reference for the MLX local AI integration in BisonHealth-AI.

## What Was Added

### New Files

```
HealthApp/HealthApp/
├── Models/
│   └── MLXModels.swift              # Model configurations and settings
├── Managers/
│   └── MLXModelManager.swift        # Model download and management
├── Services/
│   └── MLXClient.swift              # MLX inference client
└── Views/
    └── MLXSettingsView.swift        # Settings UI
```

### Modified Files

1. **SettingsManager.swift**
   - Added `AIProvider.mlx` enum case
   - Added `mlxSettings` and `mlxGenerationConfig` properties
   - Added `getMLXClient()`, `hasValidMLXConfig()`, `invalidateMLXClient()` methods
   - Added MLX settings persistence

2. **AIChatManager.swift**
   - Added MLX case to `checkConnection()`
   - Added MLX streaming support in `sendStreamingMessage()`

3. **AIProviderInterface.swift**
   - Already compatible - MLXClient implements this protocol

## Package Dependencies Required

Add these packages in Xcode:

1. **MLX Swift**: `https://github.com/ml-explore/mlx-swift`
   - Products: MLX, MLXNN, MLXRandom

2. **MLX Swift LM**: `https://github.com/ml-explore/mlx-swift-lm`
   - Products: MLXLLM, MLXLMCommon

## How to Add Packages

1. Open `HealthApp/HealthApp.xcodeproj` in Xcode
2. Select project → HealthApp target → Frameworks, Libraries, and Embedded Content
3. Click "+" → "Add Package Dependency"
4. Enter package URL and add required products

## Quick Test

After adding packages and building:

1. Run the app
2. Go to Settings → AI Provider
3. Select "MLX (On-Device)"
4. Go to MLX Settings
5. Download "MedGemma 4B (4-bit)"
6. Select it as the active model
7. Return to Chat and test a conversation

## Key Features

### Model Management
- Download models from HuggingFace
- Track download progress
- Manage local model storage
- Delete unused models

### Generation Parameters
- **Temperature**: Control creativity (0.0-2.0)
- **Top-P**: Nucleus sampling (0.0-1.0)
- **Max Tokens**: Response length (256-4096)
- **Repetition Penalty**: Reduce repetition (1.0-2.0)

### Presets
- **Precise**: Low temperature, focused responses
- **Default**: Balanced settings
- **Creative**: High temperature, diverse responses

## Model Included

| Model | Size | Context | Specialization |
|-------|------|---------|----------------|
| **MedGemma 4B (4-bit)** | 2.5 GB | 8K tokens | Medical conversations and health discussions |

## System Requirements

- iOS 17.0+
- 6GB+ RAM (8GB+ recommended)
- 3+ GB storage for MedGemma model
- iPhone 14 Pro+ or iPad Pro (M1+) recommended

## Architecture

```
User → AIChatManager
         ↓
    SettingsManager.getMLXClient()
         ↓
    MLXClient (implements AIProviderInterface)
         ↓
    MLXModelManager (handles model lifecycle)
         ↓
    MLX Swift LM (Apple's MLX framework)
         ↓
    Local Model Files (downloaded from HuggingFace)
```

## Privacy

- ✅ 100% on-device inference
- ✅ No network after model download
- ✅ Zero data transmission
- ✅ Works completely offline
- ✅ Same encryption as other app data

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build errors | Add MLX Swift packages |
| Download fails | Check internet and storage |
| Out of memory | Use smaller model, close apps |
| Slow generation | Normal on non-M-series chips |

## Next Steps

1. Add packages (required for compilation)
2. Build and test
3. Download MedGemma 4B model
4. Test chat functionality
5. Adjust generation parameters as needed

## Code Examples

### Checking if MLX is Available

```swift
if settingsManager.modelPreferences.aiProvider == .mlx {
    let hasModel = settingsManager.hasValidMLXConfig()
    // true if model downloaded and selected
}
```

### Getting Current Model

```swift
if let modelId = settingsManager.modelPreferences.mlxModelId {
    let model = MLXModelManager.shared.getLocalModel(modelId)
    print("Using: \(model?.config.name ?? "unknown")")
}
```

### Downloading a Model

```swift
let model = MLXModelRegistry.recommendedModel()
Task {
    try await MLXModelManager.shared.downloadModel(model)
}
```

### Adjusting Generation

```swift
settingsManager.mlxGenerationConfig.temperature = 0.5
settingsManager.mlxGenerationConfig.maxTokens = 1024
settingsManager.saveSettings()
```

## Performance Tips

1. **Use MedGemma 4B** for best balance of quality/speed
2. **Enable GPU** (automatic on M-series chips)
3. **Reduce max tokens** if responses too slow
4. **Close background apps** to free memory
5. **Use Precise preset** for faster, focused responses

## Future Improvements

See `MLX_INTEGRATION_GUIDE.md` for planned enhancements.

---

**Need Help?** See full guide: `MLX_INTEGRATION_GUIDE.md`
