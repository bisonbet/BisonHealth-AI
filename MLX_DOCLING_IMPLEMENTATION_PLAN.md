# Local Docling (Granite-Docling) Implementation Plan

## 🎯 Objective
Replace the remote Docling server with a local, on-device version using the `ibm-granite/granite-docling-258M-mlx` model via the MLX framework.

## 📊 Feasibility Analysis

**Status:** 🟨 **Possible, but requires significant engineering.**

The current `MLXClient` in your app relies on `MLXLMCommon` and `ChatEngine`, which are designed for **Text-only LLMs** (Llama, Phi, Gemma). 

`granite-docling` is a **Vision-Language Model (VLM)**. To run it, we need three missing components that are not currently in your MLX integration:

1.  **Vision Encoder Architecture**: Code to define the vision transformer (likely SigLIP or similar) in Swift.
2.  **Multi-modal Input Pipeline**: Code to process images (resize, normalize) and feed them into the model alongside text tokens.
3.  **Structured Output Parser**: Code to convert the model's markdown/JSON output into the `ProcessedDocumentResult` format your app expects.

## 🛠️ Implementation Steps

### Phase 1: Model Architecture (The Hard Part)
We cannot just "load" the model weights. We need Swift code that defines the model structure layer-by-layer (Linear, Conv2D, Attention) to match `granite-docling`.

- **Action:** Port the PyTorch/Python model definition to Swift/MLX.
- **Reference:** Check if `mlx-swift-examples` has a `LLaVA` or `Qwen-VL` implementation. Granite-Docling likely shares architecture with one of these.

### Phase 2: Image Processing Pipeline
Vision models expect input images to be tensors of specific shapes (e.g., `1x3x384x384`) with specific normalization (mean/std).

- **Action:** Implement `MLXImageProcessor` using `CoreGraphics` or `Accelerate` to convert `UIImage` → `MLXArray`.

### Phase 3: The `MLXDoclingClient`
Create a service that mimics the remote `DoclingClient` but runs locally.

```swift
class MLXDoclingClient: ObservableObject {
    func processDocument(_ data: Data) async throws -> ProcessedDocumentResult {
        // 1. Convert PDF to Images (CoreGraphics)
        // 2. Load Model (if not loaded)
        // 3. For each page:
        //    - Encode Image
        //    - Generate Text (Markdown)
        // 4. Combine results
    }
}
```

### Phase 4: Integration
Update `DocumentProcessor` to switch between `Remote` and `Local` processing based on user settings.

## ⚠️ Hardware Requirements
- **RAM:** The 258M model is tiny (~500MB). It will easily fit on any modern iPhone/iPad.
- **Compute:** MLX is highly optimized for Apple Silicon. Inference should be fast (seconds per page).

## 🚀 Recommended Next Step
Since writing the full model architecture from scratch is complex, I recommend:
1.  **Verify Architecture:** Find out exactly what architecture `granite-docling` uses (is it generic LLaVA? SigLIP + Llama?).
2.  **Wait/Search for Swift Port:** Look for an existing `mlx-swift` implementation of that specific architecture.
3.  **Integration:** Once we have the model definition file (e.g. `GraniteDoclingModel.swift`), the rest of the integration is straightforward.
