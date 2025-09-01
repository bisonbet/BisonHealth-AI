export interface ModelPreference {
    id: string;
    name: string;
    isPrefix?: boolean; // If true, matches any model starting with this id
}

// List of preferred models for chat, in order of preference
export const CHAT_MODEL_PREFERENCES: ModelPreference[] = [
    { id: "phi4-reasoning", name: "Phi4 Reasoning (any variant)", isPrefix: true },
    { id: "magistral", name: "Magistral (any variant)", isPrefix: true },
    { id: "qwen3:32b", name: "Qwen 3 32B" },
    { id: "qwen3:30b", name: "Qwen 3 30B" },
    { id: "qwen3:14b", name: "Qwen 3 14B" }
];

// List of preferred models for vision/document parsing, in order of preference
// Note: Larger models are more reliable for complex PDF parsing but require more resources
export const VISION_MODEL_PREFERENCES: ModelPreference[] = [
    { id: "mistral-small3.2", name: "Mistral Small 3.2 (any variant)", isPrefix: true },
    { id: "qwen2.5vl:72b", name: "Qwen 2.5 VL 72B" },
    { id: "qwen2.5vl:32b", name: "Qwen 2.5 VL 32B" },
    { id: "qwen2.5vl:7b", name: "Qwen 2.5 VL 7B" },
    { id: "gemma3:27b", name: "Gemma 3 27B" },
    { id: "gemma3:12b", name: "Gemma 3 12B" },
    { id: "llama3.2-vision:11b", name: "Llama 3.2 Vision 11B" }
];

// Helper function to get the first available model from a list of preferences
export async function getFirstAvailableModel(preferences: ModelPreference[]): Promise<ModelPreference | null> {
    const ollamaApiUrl = process.env.NEXT_PUBLIC_OLLAMA_URL || "http://ollama:11434";
    
    try {
        const response = await fetch(`${ollamaApiUrl}/api/tags`);
        if (!response.ok) {
            console.error(`Failed to fetch models from Ollama: ${response.status}`);
            return null;
        }

        const data = await response.json();
        const availableModels = new Set(data.models.map((m: { model: string }) => m.model));

        // Find the first preferred model that is available
        for (const preference of preferences) {
            if (preference.isPrefix) {
                // For prefix matching, find any model that starts with this id
                const matchingModel = data.models.find((m: { model: string, name: string }) => 
                    m.model.startsWith(preference.id)
                );
                if (matchingModel) {
                    return { id: matchingModel.model, name: matchingModel.name };
                }
            } else {
                // For exact matching
                if (availableModels.has(preference.id)) {
                    return preference;
                }
            }
        }

        // If no preferred model is available, return the first available model
        if (data.models.length > 0) {
            const firstModel = data.models[0];
            return { id: firstModel.model, name: firstModel.name };
        }

        return null;
    } catch (error) {
        console.error('Error checking available models:', error);
        return null;
    }
} 