import {
    BaseVisionParser,
    VisionModelOptions,
    VisionParseOptions,
    VisionParserModel
} from "@/lib/health-data/parser/vision/base-vision";

import {HealthCheckupSchema, HealthCheckupType} from "@/lib/health-data/parser/schema";
import {ChatOllama} from "@langchain/ollama";
import {ChatPromptTemplate} from "@langchain/core/prompts";
import {currentDeploymentEnv} from "@/lib/current-deployment-env";
import { JsonOutputParser } from "@langchain/core/output_parsers";
import { ZodError } from "zod"; // Assuming zod is used for HealthCheckupSchema

export class OllamaVisionParser extends BaseVisionParser {

    private _apiUrl: string = process.env.NEXT_PUBLIC_OLLAMA_URL || 'http://ollama:11434';

    get apiKeyRequired(): boolean {
        return false
    }

    get enabled(): boolean {
        return currentDeploymentEnv === 'local';
    }

    get apiUrlRequired(): boolean {
        return true;
    }

    get name(): string {
        return 'Ollama'
    }

    get apiUrl(): string {
        return this._apiUrl;
    }

    async models(options?: VisionModelOptions): Promise<VisionParserModel[]> {
        try {
            const apiUrl = options?.apiUrl || this._apiUrl
            const response = await fetch(`${apiUrl}/api/tags`)
            // Assuming the response is JSON and has a 'models' property
            const data = await response.json() as { models: { name: string, model: string }[] };
            
            // Filter models that have vision capabilities
            const visionModels = await Promise.all(
                data.models.map(async (m) => {
                    try {
                        const showResponse = await fetch(`${apiUrl}/api/show`, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                            },
                            body: JSON.stringify({ model: m.model })
                        });
                        const showData = await showResponse.json();
                        // Check if the model has vision capability
                        const hasVision = showData.capabilities?.includes('vision');
                        return hasVision ? {id: m.model, name: m.name} : null;
                    } catch (e) {
                        console.error(`Failed to check capabilities for model ${m.model}:`, e);
                        return null;
                    }
                })
            );
            
            // Filter out null values (models without vision capabilities)
            return visionModels.filter((model): model is VisionParserModel => model !== null);
        } catch (e) {
            console.error(e)
            return []
        }
    }

    async parse(options: VisionParseOptions): Promise<HealthCheckupType> {
        const apiUrl = options.apiUrl || this._apiUrl;
        
        // Health check: Verify Ollama is responsive and model is available
        try {
            const healthResponse = await Promise.race([
                fetch(`${apiUrl}/api/tags`, { method: 'GET' }),
                new Promise<never>((_, reject) => 
                    setTimeout(() => reject(new Error('Health check timeout')), 10000)
                )
            ]);
            if (!healthResponse.ok) {
                throw new Error(`Ollama health check failed: ${healthResponse.status}`);
            }
            
            // Check if the specific model is available
            const tagsData = await healthResponse.json() as { models: { name: string }[] };
            const modelExists = tagsData.models.some(m => m.name === options.model.id);
            if (!modelExists) {
                throw new Error(`Model ${options.model.id} is not available in Ollama. Please pull the model first: ollama pull ${options.model.id}`);
            }
            
            console.log(`Ollama health check passed. Model ${options.model.id} is available.`);
        } catch (error) {
            console.error('Ollama health check failed:', error);
            if (error instanceof Error && error.message.includes('Model')) {
                throw error; // Re-throw model-specific errors
            }
            throw new Error('Ollama server is not responding. Please check if Ollama is running and accessible.');
        }
        
        const llm = new ChatOllama({
            model: options.model.id,
            baseUrl: apiUrl,
            format: "json",
            numPredict: -1, // Corrected to camelCase
            // Increase temperature slightly for better JSON generation
            temperature: 0.1,
        });
        const messages = options.messages || ChatPromptTemplate.fromMessages([]);
        // <<< --- ADDED LOGGING HERE --- >>>
        // console.log("Ollama Prompt Messages Input (options.messages):", JSON.stringify(options.messages, null, 2));

        const chain = messages.pipe(llm).pipe(new JsonOutputParser());

        try {
            console.log(`Attempting to parse with Ollama model: ${options.model.id}`);
            
            // Create a timeout wrapper for the chain invocation
            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error('Ollama request timed out after 5 minutes')), 300000);
            });
            
            // Enhanced retry logic with exponential backoff for Ollama
            const chainPromise = chain.withRetry({ 
                stopAfterAttempt: 3,
                onFailedAttempt: (error) => {
                    console.warn(`Ollama attempt ${error.attemptNumber} failed:`, error.message);
                    // Add delay between retries for Ollama to recover
                    return new Promise(resolve => setTimeout(resolve, error.attemptNumber * 2000));
                }
            }).invoke(options.input);
            
            // Race between the chain execution and timeout
            const result = await Promise.race([chainPromise, timeoutPromise]);

            // console.log("Ollama Raw JSON Output:", result);

            let dataToValidate: unknown = result;
            
            // Combined Transformation Logic Block Start
            const expectedKey = 'test_result';
            // Add other potential incorrect container keys here
            const potentialIncorrectKeys = ['test_results', 'testResults', 'results', 'testResult']; 

            if (dataToValidate && typeof dataToValidate === 'object') {
                const dataObject = dataToValidate as { [key: string]: unknown };

                // Case 1: Correct key is missing, check for known incorrect keys
                if (!(expectedKey in dataObject)) {
                    let foundIncorrectKey: string | null = null;
                    for (const key of potentialIncorrectKeys) {
                        if (key in dataObject) {
                            foundIncorrectKey = key;
                            break;
                        }
                    }

                    // Subcase 1.1: A known incorrect key was found (e.g., 'test_results')
                    if (foundIncorrectKey) {
                        // console.log(`Transforming key: Renaming '${foundIncorrectKey}' to '${expectedKey}' and extracting value...`);
                        // Preserve other potential top-level keys (like date/name) alongside the incorrect test key
                        const baseData: { [key: string]: unknown } = {};
                        for (const topKey in dataObject) {
                            if (topKey !== foundIncorrectKey) {
                                baseData[topKey] = dataObject[topKey];
                            }
                        }
                        // Assign the extracted value (the actual tests object) to the correct key
                        dataToValidate = {
                            ...baseData,
                            [expectedKey]: dataObject[foundIncorrectKey] 
                        };
                        // console.log("Transformed Data (Incorrect Key Renamed):", dataToValidate);
                    } 
                    // Subcase 1.2: Correct key is missing AND no known incorrect keys were found
                    // Assume the entire object is the flat test data that needs wrapping.
                    else {
                        // console.warn(`Expected key '${expectedKey}' not found, and no known alternatives found. Assuming the entire result object needs to be nested under '${expectedKey}'. Performing structural transformation.`);
                        dataToValidate = { [expectedKey]: dataToValidate };
                        // console.log("Transformed Data (Structurally Wrapped):", dataToValidate);
                    }
                }
                // Case 2: Correct key ('test_result') was already present - do nothing.
                else {
                   // console.log(`Correct key '${expectedKey}' found. No transformation needed.`);
                }
            }
            // Combined Transformation Logic Block End

            // Explicitly validate the potentially transformed JSON against the Zod schema
            const validatedResult = HealthCheckupSchema.parse(dataToValidate);
            // console.log("Ollama Parsed and Validated Result:", validatedResult);
            return validatedResult;

        } catch (e: unknown) {
            console.error(`Error parsing health data with Ollama model ${options.model.id}:`, e);
            
            // Add specific error context for debugging
            if (e instanceof Error) {
                console.error('Error details:', {
                    message: e.message,
                    name: e.name,
                    stack: e.stack,
                    cause: e.cause,
                    modelId: options.model.id,
                    apiUrl: apiUrl
                });
                
                // Check for specific Ollama timeout/connection errors
                if (e.message.includes('timeout') || e.message.includes('TIMEOUT') || 
                    e.message.includes('Headers Timeout') || e.message.includes('UND_ERR_HEADERS_TIMEOUT')) {
                    console.warn(`Ollama timeout detected for model ${options.model.id}. Consider using a larger model or reducing PDF complexity.`);
                }
                
                if (e.message.includes('fetch failed') || e.message.includes('ECONNREFUSED')) {
                    console.warn(`Ollama connection failed. Please verify Ollama is running at ${apiUrl}`);
                }
            }

            // Check if it's a Zod validation error or a general parsing error (including stream and timeout)
            if (e instanceof ZodError || (e instanceof Error && (e.message.includes('json') || e.message.includes('parse') || e.message.includes('stream') || e.message.includes('timeout')))) {
                console.warn(`Ollama model ${options.model.id} failed to produce valid JSON conforming to schema or stream failed. Returning default object.`);
                // Return default object with required structure on failure
                return { test_result: {} } as HealthCheckupType;
            }
            // Re-throw other unexpected errors
            throw e;
        }
    }
}
