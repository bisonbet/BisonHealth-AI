#!/bin/bash

# Start Ollama in the background.
/bin/ollama serve &
# Record Process ID.
pid=$!

# Pause for Ollama to start.
sleep 5

echo "🔴 Retrieving necessary models..."
ollama pull qwen2.5vl:7b
echo "🟢 Done!"

# Wait for Ollama process to finish.
wait $pid
