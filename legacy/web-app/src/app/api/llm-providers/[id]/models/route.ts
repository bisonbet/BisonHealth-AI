import {NextResponse} from "next/server";
import {auth} from "@/auth";

export interface LLMProviderModel {
    id: string
    name: string
}

export interface LLMProviderModelListResponse {
    llmProviderModels: LLMProviderModel[]
}

export async function GET() {
    const session = await auth()
    if (!session || !session.user) {
        return NextResponse.json({error: 'Unauthorized'}, {status: 401})
    }

    try {
        const ollamaApiUrl = process.env.NEXT_PUBLIC_OLLAMA_URL || "http://ollama:11434";
        const listModelsUrl = new URL("/api/tags", ollamaApiUrl).toString();

        console.log(`Attempting to fetch models from Ollama at: ${listModelsUrl}`);
        const response = await fetch(listModelsUrl);

        if (!response.ok) {
            console.error(`Ollama API request failed: ${response.status} ${response.statusText}`);
            const errorBody = await response.text();
            console.error("Ollama Error Body:", errorBody);
            return NextResponse.json<LLMProviderModelListResponse>({ llmProviderModels: [] }, { status: response.status });
        }

        const data = await response.json();

        if (!data || !Array.isArray(data.models)) {
            console.error("Invalid response structure from Ollama /api/tags");
            return NextResponse.json<LLMProviderModelListResponse>({ llmProviderModels: [] }, { status: 500 });
        }

        // Filter models that don't have embedding capability
        const nonEmbeddingModels = await Promise.all(
            data.models.map(async (model: { name: string, model: string }) => {
                try {
                    const showResponse = await fetch(`${ollamaApiUrl}/api/show`, {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                        },
                        body: JSON.stringify({ model: model.model })
                    });
                    const showData = await showResponse.json();
                    // Check if the model does NOT have embedding capability
                    const hasEmbedding = showData.capabilities?.includes('embedding');
                    return !hasEmbedding ? { id: model.model, name: model.name } : null;
                } catch (e) {
                    console.error(`Failed to check capabilities for model ${model.model}:`, e);
                    return null;
                }
            })
        );

        const models: LLMProviderModel[] = nonEmbeddingModels.filter((model): model is LLMProviderModel => model !== null);

        return NextResponse.json<LLMProviderModelListResponse>({
            llmProviderModels: models,
        });

    } catch (error: unknown) {
        console.error(`Error fetching models from Ollama:`, error);
        return NextResponse.json<LLMProviderModelListResponse>({ llmProviderModels: [] }, { status: 500 });
    }
}
