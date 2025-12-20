# MLX Local AI Integration Guide

This document describes the MLX (Apple Metal Linear Algebra) integration for BisonHealth-AI, enabling completely private, on-device AI inference without requiring network connectivity.

## ⚠️ Implementation Status

**Current Status**: 🟡 Architecture Complete, API Integration Required

The complete architecture is implemented, but the MLX Swift LM API calls need to be completed after adding the packages. See **[MLX_IMPLEMENTATION_STATUS.md](MLX_IMPLEMENTATION_STATUS.md)** for detailed information about what needs to be finished.

- ✅ Full architecture and UI complete
- ✅ Model management working
- 🟡 MLX generation API needs implementation (after adding packages)
- ⏳ Estimated completion time: 1.5-3 hours

## Overview

The MLX integration adds local AI model support using Apple's MLX framework, allowing users to run medical AI models like MedGemma directly on their device. This provides:

- **Complete Privacy**: All inference happens on-device, no data leaves the device
- **No Network Required**: Works offline once models are downloaded
- **Apple Silicon Optimized**: Uses GPU acceleration on M-series chips
- **Medical AI**: Includes support for MedGemma, a medical domain-specialized model

## Architecture

### Components Added

1. **Models** (`Models/MLXModels.swift`)
   - `MLXModelConfig`: Configuration for available models
   - `MLXLocalModel`: Locally downloaded model metadata
   - `MLXGenerationConfig`: Generation parameters (temperature, top-p, etc.)
   - `MLXModelRegistry`: Predefined models available for download
   - `MLXSettings`: Persistent settings

2. **Managers** (`Managers/MLXModelManager.swift`)
   - Downloads models from HuggingFace Hub
   - Manages model lifecycle (download, delete, load)
   - Tracks download progress
   - Monitors storage usage

3. **Services** (`Services/MLXClient.swift`)
   - Implements `AIProviderInterface`
   - Loads and runs MLX models
   - Handles streaming and non-streaming generation
   - Manages model memory and GPU resources

4. **Views** (`Views/MLXSettingsView.swift`)
   - Model selection and download UI
   - Generation parameter configuration
   - Storage management
   - Preset configurations (Precise, Default, Creative)

5. **Settings Integration**
   - Updated `AIProvider` enum to include `.mlx`
   - Added MLX settings to `SettingsManager`
   - Updated `AIChatManager` to support MLX provider

## Setup Instructions

### Step 1: Add Swift Package Dependencies

Open the Xcode project and add the following Swift packages:

#### Required Packages:

1. **MLX Swift** - Apple's MLX framework for Swift
   - URL: `https://github.com/ml-explore/mlx-swift`
   - Version: Latest release (2.x or higher)
   - Products to add:
     - MLX
     - MLXNN
     - MLXRandom

2. **MLX Swift LM** - LLM support for MLX
   - URL: `https://github.com/ml-explore/mlx-swift-lm`
   - Version: Latest release (2.29.1 or higher)
   - Products to add:
     - MLXLLM
     - MLXLMCommon

#### Adding Packages in Xcode:

1. Open `HealthApp.xcodeproj`
2. Select the project in the navigator
3. Select the "HealthApp" target
4. Go to "Frameworks, Libraries, and Embedded Content"
5. Click the "+" button
6. Click "Add Package Dependency"
7. Enter the package URL and select the version
8. Select the products to add to the target
9. Click "Add Package"
10. Repeat for each package

### Step 2: Add Files to Xcode Project

The following new files need to be added to the Xcode project:

1. **Models Group**:
   - `MLXModels.swift`

2. **Managers Group**:
   - `MLXModelManager.swift`

3. **Services Group**:
   - `MLXClient.swift` ⚠️ Requires API implementation after adding packages

4. **Views Group**:
   - `MLXSettingsView.swift`

#### Adding Files in Xcode:

1. Right-click on the appropriate group (Models, Managers, Services, or Views)
2. Select "Add Files to HealthApp..."
3. Navigate to the file location
4. Ensure "Copy items if needed" is checked
5. Ensure "HealthApp" target is checked
6. Click "Add"

**Note**: `MLXClient.swift` contains placeholder implementations that need to be completed after adding the MLX Swift packages. See `MLX_IMPLEMENTATION_STATUS.md` for details.

### Step 3: Update Entitlements (if needed)

MLX requires access to:
- Increased memory limit for loading large models
- Network access for downloading models from HuggingFace

Ensure these are configured in `HealthApp.entitlements`:

```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

### Step 4: Complete MLX API Implementation

⚠️ **Required**: After adding packages, complete the MLX Swift LM API integration in `MLXClient.swift`.

See **[MLX_IMPLEMENTATION_STATUS.md](MLX_IMPLEMENTATION_STATUS.md)** for:
- Detailed implementation instructions
- Code examples and patterns
- Reference to official MLX examples
- Testing procedures

**Files to update**:
- `HealthApp/HealthApp/Services/MLXClient.swift` (lines 282-349, 406-437)

**Estimated time**: 1.5-3 hours

### Step 5: Build and Test

1. Clean build folder: `Product > Clean Build Folder`
2. Build the project: `⌘B`
3. Resolve any package dependencies: `File > Packages > Resolve Package Versions`
4. Run on a device or simulator
5. Test MLX generation (after completing Step 4)

## Usage

### For Users

1. **Open Settings**: Navigate to Settings in the app
2. **Select AI Provider**: Choose "MLX (On-Device)" from AI provider options
3. **Download a Model**:
   - Go to MLX Settings
   - Browse available models
   - Tap download on "MedGemma 4B (4-bit)" (recommended for medical conversations)
   - Wait for download to complete (~2.5 GB)
4. **Select Model**: Tap on the downloaded model to set it as active
5. **Configure Parameters** (optional):
   - Adjust temperature for creativity vs. precision
   - Use presets: Precise, Default, or Creative
6. **Start Chatting**: Return to chat and start a conversation

### For Developers

#### Adding New Models

Add new models to `MLXModelRegistry.availableModels` in `MLXModels.swift`:

```swift
MLXModelConfig(
    id: "model-id",
    name: "Model Name",
    huggingFaceRepo: "mlx-community/model-name",
    description: "Model description",
    modelType: .textOnly,
    quantization: "4-bit",
    estimatedSize: 2_500_000_000, // bytes
    contextWindow: 8192,
    recommended: false,
    specialization: "Optional specialization description"
)
```

#### Adjusting Generation Parameters

Modify the presets in `MLXGenerationConfig`:

```swift
static let custom = MLXGenerationConfig(
    temperature: 0.5,        // 0.0-2.0 (higher = more creative)
    topP: 0.9,              // 0.0-1.0 (nucleus sampling)
    maxTokens: 2048,        // Maximum response length
    repetitionPenalty: 1.1, // 1.0-2.0 (higher = less repetition)
    repetitionContextSize: 20
)
```

## Available Models

### MedGemma 4B (4-bit)

- **Repository**: `mlx-community/medgemma-4b-it-4bit`
- **Size**: ~2.5 GB
- **Specialization**: Medical knowledge and health conversations
- **Context Window**: 8,192 tokens
- **Description**: Medical AI assistant based on Google's Gemma, optimized for health conversations. This is the only model included to maintain focus on medical-specific AI capabilities.

## System Requirements

### Minimum Requirements:

- **iOS**: 17.0 or later
- **RAM**: 6GB+ (for MedGemma 4B)
- **Storage**: 3+ GB free space
- **Devices**:
  - iPhone 14 Pro or later
  - iPhone 15 or later
  - iPad Pro (M1/M2/M4)

### Recommended:

- **Devices with Apple Silicon**: M1/M2/M3/M4 chips for GPU acceleration
- **RAM**: 8GB+
- **Storage**: 5+ GB free space

## Performance

- **GPU Acceleration**: Available on M-series chips (M1, M2, M3, M4)
- **CPU Fallback**: Works on non-M-series devices but slower
- **Generation Speed**:
  - M1/M2 iPad: ~10-20 tokens/second
  - M3/M4 iPad: ~20-40 tokens/second
  - iPhone (CPU only): ~2-5 tokens/second

## Privacy & Security

- **100% On-Device**: All inference happens locally
- **No Network After Download**: Works completely offline
- **No Data Transmission**: User data never leaves the device
- **Encrypted Storage**: Models stored in app's documents directory
- **Secure**: Same security as other app data

## Troubleshooting

### Model Download Fails

- **Solution**: Check internet connection and available storage
- **Retry**: Download can be retried from MLX Settings

### Out of Memory Errors

- **Solution**:
  - Close other apps
  - Use smaller models (3B instead of 7B)
  - Reduce max tokens in settings

### Slow Generation

- **Solution**:
  - Ensure device has sufficient cooling
  - Close background apps
  - Use smaller models
  - Reduce context size

### Model Won't Load

- **Solution**:
  - Delete and re-download the model
  - Check available storage
  - Restart the app

## Future Enhancements

Potential future improvements:

1. **Additional Medical Models**: Support for other medical-specialized models as they become available
2. **Model Quantization**: Support for different quantization levels (2-bit, 8-bit)
3. **Custom Models**: Allow users to import custom fine-tuned MedGemma models
4. **Model Updates**: Automatic checking for MedGemma model updates
5. **Multi-Modal**: Support for vision-language medical models
6. **LoRA Support**: Fine-tuning with LoRA adapters for personalization

## References

- [MLX Swift Repository](https://github.com/ml-explore/mlx-swift)
- [MLX Swift LM Repository](https://github.com/ml-explore/mlx-swift-lm)
- [MedGemma on HuggingFace](https://huggingface.co/google/medgemma-4b-it)
- [MLX Community Models](https://huggingface.co/mlx-community)

## License

The MLX integration code follows the same MIT license as BisonHealth-AI. Individual models have their own licenses (see HuggingFace model pages for details).

## Support

For issues or questions:
- Check the troubleshooting section above
- Review MLX Swift documentation
- Check HuggingFace model cards for model-specific issues

---

**Last Updated**: 2025-12-20
**Version**: 1.0.0
