import {OllamaVisionParser} from "@/lib/health-data/parser/vision/ollama";

const visions = [
    new OllamaVisionParser(),
].filter(v => v.enabled)

export default visions
