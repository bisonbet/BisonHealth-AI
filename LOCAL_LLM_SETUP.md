# Local LLM Setup Guide

This document provides instructions for setting up the local LLM functionality in BisonHealth-AI.

## Overview

BisonHealth-AI now supports on-device AI inference using medical-specialized models. This feature allows users to chat with AI doctors completely offline with complete privacy - no data ever leaves the device.

## Implementation Summary

The following components have been added to support local LLM functionality:

### Core Files Created

1. **OnDeviceLLM/OnDeviceLLMModels.swift**
   - Model definitions for MedGemma-4B and Qwen3-VL-4B
   - Quantization options (Q4_K_M, Q5_K_M, Q8_0)
   - Configuration management via UserDefaults
   - Error handling

2. **OnDeviceLLM/ModelDownloadManager.swift**
   - Background model downloads from HuggingFace
   - Network monitoring (WiFi/cellular)
   - Download progress tracking
   - Storage management and validation
   - Resume/cancel functionality

3. **OnDeviceLLM/OnDeviceLLMService.swift**
   - LLM inference engine using LocalLLMClient
   - Model loading/unloading
   - Text generation (batch and streaming)
   - Vision model support for image analysis
   - Medical analysis helpers
   - Memory management

4. **OnDeviceLLM/OnDeviceLLMSettingsView.swift**
   - SwiftUI settings interface
   - Model selection and download UI
   - Quantization picker
   - Storage management
   - Advanced settings (temperature, max tokens)
   - Help and documentation

5. **Services/LocalLLMProvider.swift**
   - Conforms to AIProviderInterface
   - Integrates with existing AI provider architecture
   - Health data context handling
   - Streaming support
   - Vision model integration

### Integration Points Modified

1. **Managers/SettingsManager.swift**
   - Added `AIProvider.localLLM` case
   - Added `getLocalLLMProvider()` method
   - Added `localLLMProvider` property

2. **Services/AIProviderInterface.swift**
   - Added `ProviderType.localLLM` case to factory

3. **Views/SettingsView.swift**
   - Added `SettingsRoute.localLLMSettings` case
   - Added `localLLMCard` view
   - Added navigation to OnDeviceLLMSettingsView

4. **HealthApp.entitlements**
   - Added `com.apple.developer.kernel.increased-memory-limit` entitlement

5. **README.md**
   - Updated with on-device AI features
   - Added model information and requirements
   - Updated architecture diagram

## Required Swift Package Dependency

**IMPORTANT**: You need to add the LocalLLMClient Swift package to the Xcode project.

### Adding the LocalLLMClient Package

1. Open the project in Xcode: `HealthApp/HealthApp.xcodeproj`

2. Go to **File → Add Package Dependencies...**

3. Enter the repository URL:
   ```
   https://github.com/tattn/LocalLLMClient.git
   ```

4. Select **Exact Version**: `0.4.6`

5. Click **Add Package**

6. When prompted, ensure these products are added to the **HealthApp** target:
   - `LocalLLMClient`
   - `LocalLLMClientLlama`

7. Click **Add Package** to confirm

### Alternative: Manual Project File Edit

If you prefer to add the dependency manually, add this to the project.pbxproj file:

```xml
/* Swift Package References */
{
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/tattn/LocalLLMClient.git";
    requirement = {
        kind = exactVersion;
        version = 0.4.6;
    };
}
```

## Model Information

### MedGemma-4B
- **Model ID**: `medgemma-4b`
- **HuggingFace Repo**: https://huggingface.co/unsloth/medgemma-4b-it-GGUF
- **Specialization**: Medical domain, trained on clinical literature
- **Context Window**: 8,192 tokens
- **Size**: ~2-4 GB depending on quantization
- **Use Case**: Medical conversations, health data analysis

### Qwen3-VL-4B
- **Model ID**: `qwen3-vl-4b`
- **HuggingFace Repo**: https://huggingface.co/unsloth/Qwen3-VL-4B-Instruct-GGUF
- **Specialization**: Vision-language model
- **Context Window**: 32,768 tokens
- **Size**: ~2-4 GB depending on quantization
- **Use Case**: Document import, medical image analysis, lab report OCR
- **Vision Support**: Can analyze images and documents

### Quantization Levels

- **Q4_K_M** (Recommended): ~2.0-2.5 GB, balanced quality and size
- **Q5_K_M**: ~2.5-3.0 GB, higher quality
- **Q8_0**: ~3.5-4.0 GB, maximum quality

## Device Requirements

- **iPhone**: iPhone 12 or newer
- **iPad**: iPad with A14 Bionic chip or later, or iPad Pro with M1 or later
- **iOS**: 17.0+
- **Storage**: 2-4 GB free space per model
- **Memory**: Increased memory limit entitlement enabled

## Usage

1. **Enable On-Device AI**
   - Open Settings → AI Provider
   - Select "On-Device AI"
   - Tap "Configure"

2. **Download a Model**
   - Choose between MedGemma-4B or Qwen3-VL-4B
   - Select quantization level (Q4_K_M recommended)
   - Tap "Download Model"
   - Wait for download to complete (WiFi recommended)

3. **Configure Settings**
   - Adjust temperature (0.0-1.0, lower = more focused)
   - Set max response length (256-8192 tokens)
   - Enable/disable cellular downloads

4. **Start Chatting**
   - Go to the Chat tab
   - Select an AI Doctor persona
   - Choose health data context
   - Start asking questions!

## Features

### Privacy
- ✅ All processing happens on-device
- ✅ No internet connection required
- ✅ No data sent to external servers
- ✅ Works completely offline

### Medical Specialization
- ✅ Models trained on medical literature
- ✅ Understanding of medical terminology
- ✅ Clinical reasoning capabilities
- ✅ Integration with health data context

### Vision Model Support (Qwen3-VL only)
- ✅ Analyze medical images
- ✅ Extract text from lab reports
- ✅ Process imaging reports
- ✅ Document understanding

### Performance
- ✅ Streaming responses for real-time chat
- ✅ Memory-efficient model loading
- ✅ Automatic model unloading during memory pressure
- ✅ Background model downloads

## Architecture Integration

The local LLM provider seamlessly integrates with the existing AI provider architecture:

```
AIChatManager
    ↓
SettingsManager.getAIClient()
    ↓
Switch on aiProvider:
    - .ollama → OllamaClient
    - .bedrock → BedrockClient
    - .openAICompatible → OpenAICompatibleClient
    - .localLLM → LocalLLMProvider ← NEW!
        ↓
    OnDeviceLLMService
        ↓
    LocalLLMClient (llama.cpp)
        ↓
    GGUF model files
```

## File Structure

```
HealthApp/HealthApp/
├── OnDeviceLLM/
│   ├── OnDeviceLLMModels.swift        # Model definitions
│   ├── ModelDownloadManager.swift     # Download management
│   ├── OnDeviceLLMService.swift       # Inference engine
│   └── OnDeviceLLMSettingsView.swift  # Settings UI
├── Services/
│   └── LocalLLMProvider.swift         # AIProviderInterface implementation
├── Managers/
│   └── SettingsManager.swift          # Updated with localLLM support
└── HealthApp.entitlements             # Updated with memory entitlement
```

## Troubleshooting

### Model Download Issues
- Ensure you have sufficient storage space
- Connect to WiFi or enable cellular downloads
- Check network connection
- Try restarting the download

### Model Loading Issues
- Verify model file exists and is complete (>500 MB)
- Check available device memory
- Try a smaller quantization level
- Restart the app

### Inference Issues
- Ensure model is loaded successfully
- Check input length doesn't exceed context window
- Verify device meets minimum requirements
- Monitor device temperature (models may throttle on hot devices)

### Memory Issues
- Use Q4_K_M quantization for better memory efficiency
- Close other apps to free memory
- Restart the app to clear memory
- Consider using a newer device with more RAM

## Future Enhancements

Potential future improvements:

1. **Model Management**
   - Auto-update models when new versions available
   - Model compression/optimization
   - Shared model storage across apps

2. **Performance**
   - Hardware acceleration optimization
   - Batch processing for multiple queries
   - Model caching and pre-warming

3. **Features**
   - Multi-modal input (text + images)
   - Fine-tuning on personal health data
   - Model selection based on query type

4. **Additional Models**
   - Specialized models for specific conditions
   - Multilingual medical models
   - Smaller models for faster responses

## References

- LocalLLMClient: https://github.com/tattn/LocalLLMClient
- MedGemma-4B: https://huggingface.co/unsloth/medgemma-4b-it-GGUF
- Qwen3-VL-4B: https://huggingface.co/unsloth/Qwen3-VL-4B-Instruct-GGUF
- llama.cpp: https://github.com/ggerganov/llama.cpp
- GGUF format: https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
