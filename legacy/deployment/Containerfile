# Stage 1: Install dependencies
# This stage is dedicated to installing npm packages. It will only be re-run
# when your package.json or package-lock.json changes, greatly speeding up builds.
FROM node:lts-alpine AS deps
WORKDIR /app

# Install dependencies needed for `npm ci`
COPY package.json package-lock.json* ./
RUN npm ci

# Stage 2: Build the application
# This stage builds your Next.js app. It re-uses the dependencies from the 'deps' stage
# and will be re-run only when your source code changes.
FROM node:lts-alpine AS builder
WORKDIR /app
# Copy dependencies from the previous stage
COPY --from=deps /app/node_modules ./node_modules
# Copy the rest of the source code. A .dockerignore file will prevent
# unnecessary files from being copied.
COPY . .

# Build the app. `npx prisma generate` is part of your `build` script.
# The `standalone` output mode in next.config.js creates a minimal build artifact.
RUN npm run build

# Stage 3: Production image
# This is the final, lean image that will be deployed. It only contains
# the minimal files and dependencies needed to run the application.
FROM node:lts-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Install only RUNTIME system dependencies. `build-base` and `-dev` packages are not needed.
RUN apk add --no-cache graphicsmagick ghostscript vips libpng poppler-utils

# Create a non-root user for security.
RUN adduser --disabled-password ohuser

# Copy the minimal application artifacts from the 'builder' stage.
COPY --from=builder --chown=ohuser:ohuser /app/.next/standalone ./
COPY --from=builder --chown=ohuser:ohuser /app/.next/static ./.next/static
COPY --from=builder --chown=ohuser:ohuser /app/public ./public
COPY --from=builder --chown=ohuser:ohuser /app/prisma ./prisma
# Create startup script inline
RUN echo '#!/bin/sh' > /app/start.sh && \
    echo 'set -e' >> /app/start.sh && \
    echo 'echo "Container starting..."' >> /app/start.sh && \
    echo 'if [ -f "prisma/data/llm-provider.json" ]; then' >> /app/start.sh && \
    echo '    echo "Substituting placeholder in prisma/data/llm-provider.json with NEXT_PUBLIC_OLLAMA_URL: [$NEXT_PUBLIC_OLLAMA_URL]"' >> /app/start.sh && \
    echo '    sed "s|\${NEXT_PUBLIC_OLLAMA_URL}|$NEXT_PUBLIC_OLLAMA_URL|g" prisma/data/llm-provider.json > prisma/data/llm-provider.json.tmp && \' >> /app/start.sh && \
    echo '    mv prisma/data/llm-provider.json.tmp prisma/data/llm-provider.json' >> /app/start.sh && \
    echo '    echo "Substitution successful."' >> /app/start.sh && \
    echo 'else' >> /app/start.sh && \
    echo '    echo "Warning: prisma/data/llm-provider.json not found. Skipping substitution."' >> /app/start.sh && \
    echo 'fi' >> /app/start.sh && \
    echo 'echo "---"' >> /app/start.sh && \
    echo 'echo "Starting application..."' >> /app/start.sh && \
    echo 'exec "$@"' >> /app/start.sh && \
    chmod +x /app/start.sh && \
    chown ohuser:ohuser /app/start.sh

USER ohuser

EXPOSE 3000

ENTRYPOINT ["sh", "/app/start.sh"]

CMD ["node", "server.js"]