# Ollama Swift Integration Guide

This document provides instructions for integrating the ollama-swift library into the BisonHealth AI project to enable streaming chat responses and advanced AI features.

## Overview

The ollama-swift library (https://github.com/bisonbet/ollama-swift) provides:
- Streaming chat responses for real-time AI interaction
- Structured output support
- Thinking/reasoning capabilities
- Better error handling and connection management
- Model management and pulling capabilities

## Integration Steps

### 1. Add Package Dependency

1. Open the BisonHealth AI project in Xcode
2. Go to **File > Add Package Dependencies...**
3. Enter the package URL: `https://github.com/bisonbet/ollama-swift.git`
4. Select version: `from: "1.8.0"`
5. Click **Add Package**
6. Select the **OllamaKit** product and add it to the **HealthApp** target

### 2. Complete the Integration

The `OllamaClient.swift` file is currently using HTTP fallbacks and contains TODO comments marking where ollama-swift integration should be completed. 

**Integration Points:**
1. **Import Statement**: Update the commented import at the top of the file
2. **Client Initialization**: Replace the HTTP session with the ollama-swift client
3. **Connection Testing**: Replace HTTP health check with ollama-swift connection test
4. **Chat Methods**: Replace HTTP requests with ollama-swift chat API
5. **Model Management**: Replace HTTP calls with ollama-swift model management
6. **Streaming**: Implement real streaming with ollama-swift streaming API

### 3. Search for TODO Comments

Search for `TODO:` in `OllamaClient.swift` to find all integration points that need to be updated.

### 4. Key Changes Made

#### OllamaClient Enhancements
- **Streaming Support**: Real-time message streaming with `sendStreamingChatMessage()`
- **Better Connection Testing**: Uses OllamaKit's built-in connection methods
- **Model Management**: Enhanced model pulling with progress tracking
- **Error Handling**: Improved error types and recovery suggestions

#### AIChatManager Enhancements
- **Streaming Messages**: Support for real-time message updates
- **Message State Management**: Handles streaming message states
- **Flexible Sending**: Option to use streaming or non-streaming modes

#### UI Enhancements
- **Real-time Updates**: MessageListView automatically scrolls during streaming
- **Streaming Indicators**: Visual feedback for messages being generated
- **iPad Optimizations**: Better keyboard shortcuts and layout for iPad

### 4. New Features Available

#### Streaming Chat
```swift
// Enable streaming for real-time responses
try await chatManager.sendMessage(message, useStreaming: true)
```

#### Model Selection
The updated client supports multiple Ollama models:
- llama3.2 (default)
- llama3.1
- llama2
- codellama

#### Progress Tracking
Model pulling now includes progress callbacks:
```swift
try await ollamaClient.pullModel("llama3.2") { progress in
    print("Download progress: \(progress * 100)%")
}
```

### 5. Configuration Options

#### Conversation Settings
Users can now configure:
- Streaming vs non-streaming responses
- Model selection
- Conversation titles

#### Health Data Context
Enhanced context management with:
- iPad-optimized selector interface
- Visual context size indicators
- Granular data type selection

### 6. Testing the Integration

After adding the package dependency:

1. **Build the project** to ensure all imports resolve correctly
2. **Test connection** to your Ollama server
3. **Verify streaming** by sending a message and observing real-time updates
4. **Test iPad features** including split-screen layout and keyboard shortcuts

### 7. Troubleshooting

#### Common Issues

**Import Errors**
- Ensure the Ollama package is properly added to the target
- Clean and rebuild the project (⌘+Shift+K, then ⌘+B)

**Connection Issues**
- Verify Ollama server is running on the configured host/port
- Check firewall settings if connecting to remote server
- Ensure the selected model is available (pull if necessary)

**Streaming Issues**
- Verify network connectivity during streaming
- Check that the model supports streaming (most Ollama models do)
- Monitor console for streaming-related errors

#### Performance Considerations

**Memory Usage**
- Streaming responses use minimal additional memory
- Long conversations may accumulate message history
- Consider implementing message cleanup for very long chats

**Network Usage**
- Streaming uses persistent connections
- Monitor network usage for mobile deployments
- Implement proper connection cleanup on app backgrounding

### 8. Future Enhancements

The ollama-swift integration enables future features:

**Structured Output**
- JSON schema-based responses
- Validated health data extraction
- Consistent response formatting

**Thinking/Reasoning**
- Step-by-step problem solving
- Transparent AI reasoning process
- Better health advice quality

**Advanced Context Management**
- Dynamic context sizing
- Intelligent context compression
- Multi-turn conversation optimization

## Implementation Status

✅ **Completed**
- Basic ollama-swift integration
- Streaming chat responses
- Enhanced UI for iPad
- Model management
- Connection testing

🔄 **In Progress**
- Structured output implementation
- Advanced error recovery
- Performance optimizations

📋 **Planned**
- Thinking/reasoning features
- Advanced context management
- Offline model support

## Dependencies

The integration adds one new dependency:
- **ollama-swift** (1.8.0+): Core Ollama client library

Existing dependencies remain:
- **SQLite.swift**: Database operations
- **SwiftUI**: User interface
- **Foundation**: Core functionality

## Compatibility

- **iOS**: 17.0+
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **Ollama Server**: 0.1.0+

The integration maintains backward compatibility with existing features while adding new streaming capabilities.