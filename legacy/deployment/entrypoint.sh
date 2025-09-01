#!/bin/sh
# Use `sh` for POSIX compatibility, as Alpine images use ash, not bash.
set -e

echo "Container starting..."

# The original Containerfile substituted a URL in a JSON file at startup.
# This is a safe way to do it.
if [ -f "prisma/data/llm-provider.json" ]; then
    echo "Substituting placeholder in prisma/data/llm-provider.json with OLLAMA_URL: [$OLLAMA_URL]"
    # Use a temporary file for sed to be safe and avoid issues with in-place editing.
    sed "s|\"apiURL\": \"\${OLLAMA_URL}\"|\"apiURL\": \"$OLLAMA_URL\"|g" prisma/data/llm-provider.json > prisma/data/llm-provider.json.tmp && \
    mv prisma/data/llm-provider.json.tmp prisma/data/llm-provider.json
    echo "Substitution successful."
else
    echo "Warning: prisma/data/llm-provider.json not found. Skipping substitution."
fi

echo "---"
echo "Starting application..."

# Execute the command passed to the entrypoint (e.g., the CMD from the Containerfile)
exec "$@"