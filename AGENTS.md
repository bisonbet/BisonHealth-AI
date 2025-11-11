# Repository Guidelines

## Project Structure & Module Organization
- iOS app: `HealthApp/HealthApp` (SwiftUI Views, ViewModels, Services, Models, Assets)
- Unit tests: `HealthApp/HealthAppTests`; UI tests: `HealthApp/HealthAppUITests`
- Xcode project: `HealthApp/HealthApp.xcodeproj` (scheme: `HealthApp`)
- Legacy reference: `legacy/` is a different app copied here for reference only (do not modify).

## Legacy Reference
- Purpose: read‑only source of ideas, data models, and UX patterns; not part of builds or releases.
- Useful paths: `legacy/web-app/src/lib/health-data/parser/*`, `legacy/Docs/specs/ios-health-app/*`.
- Do not directly import JS/Next.js code into Swift; port concepts with native APIs.
- Only touch `legacy/` when explicitly migrating or documenting references.

## Build, Test, and Development Commands
- Open in Xcode: `open HealthApp/HealthApp.xcodeproj`
- Build (CLI, Simulator default): `xcodebuild -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
- Unit/UI tests (Simulator): `xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- Legacy web-app (optional, reference only): `cd legacy/web-app && npm i && npm run dev` (unsupported)

Note: Our default Simulator target is `iPhone 16 Pro`. If that runtime isn't installed locally, either install it via Xcode > Settings > Platforms or temporarily substitute another available device (e.g., `iPhone 15`).

### AI Agent Guidelines for Build Commands
- **DO NOT run `xcodebuild` commands unless the user explicitly requests a build or test run**
- Use `read_lints` tool to check for compilation errors instead of building
- Only run builds when:
  - User explicitly asks to build, test, or verify compilation
  - User asks to check if something compiles
  - User requests running tests
- For checking code correctness, prefer static analysis tools (linter) over building

## Coding Style & Naming Conventions
- Swift: follow Apple’s Swift API Design Guidelines; 4‑space indentation; no force‑unwraps.
- Naming: `PascalCase` types, `lowerCamelCase` vars/functions; files match primary type (e.g., `DocumentProcessor.swift`).
- Structure Swift files with `// MARK:` for Properties, Init, Public/Private methods.
- SwiftUI: Views end with `View` (e.g., `DocumentListView`); keep subviews as private computed properties.
- Legacy web-app: TypeScript + ESLint (see `legacy/web-app/eslint.config.mjs`).

## Testing Guidelines
- Framework: XCTest for unit and UI tests.
- Location: mirror source structure under `HealthAppTests` and `HealthAppUITests`.
- Naming: test files end with `Tests.swift`; methods start with `test...` and assert observable behavior.
- Coverage: add tests for new logic; prefer constructor injection for services to enable mocking.
- Run: use the scheme `HealthApp` with the iOS Simulator destination (see commands above).

## Commit & Pull Request Guidelines
- Commits: use Conventional Commits (e.g., `feat:`, `fix:`, `docs:`) as seen in history.
- PRs: include clear description, linked issues, test evidence, privacy impact notes, and screenshots for UI changes.
- CI expectations: builds cleanly, tests pass, no new warnings.

## Security & Configuration Tips
- Do not commit secrets or PHI. Data is local and encrypted; follow patterns in `Services/` and `Database` usage.
- Network calls must use TLS and validate responses (see `OllamaClient.swift`, `DoclingClient.swift`).
- For AI integration details, see `HealthApp/OLLAMA_SWIFT_INTEGRATION.md`.
