#!/bin/bash

# Docker build optimization script
set -e

echo "🚀 Starting optimized Docker build..."

# Check if .env file exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please create one based on .env.example"
    exit 1
fi

# Load environment variables
set -a  # automatically export all variables
source .env
set +a  # stop automatically exporting

# Build with BuildKit for better caching and parallelization
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Clean up any existing containers and images (optional)
read -p "🧹 Do you want to clean up existing containers and images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 Cleaning up existing containers and images..."
    docker compose down --remove-orphans
    docker system prune -f
    docker builder prune -f
fi

# Build with optimized settings
echo "🔨 Building with optimized Containerfile..."

# Use the optimized Containerfile
if [ -f "Containerfile.optimized" ]; then
    echo "📋 Using optimized Containerfile..."
    cp Containerfile Containerfile.backup
    cp Containerfile.optimized Containerfile
fi

docker compose build \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --build-arg OLLAMA_URL="${OLLAMA_URL}" \
    --build-arg DOCLING_URL="${DOCLING_URL}" \
    --build-arg AUTH_SECRET="${AUTH_SECRET}" \
    --build-arg ENCRYPTION_KEY="${ENCRYPTION_KEY}" \
    --build-arg NEXT_PUBLIC_URL="${NEXT_PUBLIC_URL}" \
    --progress=plain \
    app

# Restore original Containerfile
if [ -f "Containerfile.backup" ]; then
    mv Containerfile.backup Containerfile
fi

echo "✅ Build completed successfully!"
echo "🚀 You can now run: docker compose up -d"