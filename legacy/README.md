# Legacy Files

This directory contains files from the original Next.js web application that was used as the foundation for the iOS health app project.

## Structure

- **web-app/**: Complete Next.js web application source code
  - React/TypeScript frontend
  - Prisma database schema
  - API routes and components
  - Configuration files (Next.js, Tailwind, ESLint, etc.)

- **deployment/**: Docker and deployment configuration
  - Containerfiles for Docker builds
  - Docker Compose configurations
  - Nginx configuration
  - Deployment scripts

- **dev-config/**: IDE and development environment configurations
  - VS Code settings
  - IntelliJ IDEA settings
  - IDX configuration

- **Docs/**: Original documentation and spec files (duplicated in .kiro/specs/)

## Purpose

These files are preserved for reference during the iOS app development process. The web application demonstrates the intended functionality and data models that should be implemented in the Swift iOS version.

## Current iOS Development

The active iOS app development is happening in the root directory with specs located in `.kiro/specs/ios-health-app/`.