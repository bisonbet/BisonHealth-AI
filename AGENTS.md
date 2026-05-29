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
- Swift: follow Apple's Swift API Design Guidelines; 4‑space indentation; no force‑unwraps.
- Naming: `PascalCase` types, `lowerCamelCase` vars/functions; files match primary type (e.g., `DocumentProcessor.swift`).
- Structure Swift files with `// MARK:` for Properties, Init, Public/Private methods.
- SwiftUI: Views end with `View` (e.g., `DocumentListView`); keep subviews as private computed properties.
- Legacy web-app: TypeScript + ESLint (see `legacy/web-app/eslint.config.mjs`).

### Adding New Files to Xcode Project
- **CRITICAL**: When creating new Swift files, they MUST be added to the Xcode project (`HealthApp/HealthApp.xcodeproj/project.pbxproj`).
- Required steps:
  1. Add PBXBuildFile entry in the PBXBuildFile section
  2. Add PBXFileReference entry in the PBXFileReference section
  3. Add file reference to the appropriate group (Utils, Models, Views, Managers, Services, etc.)
  4. Add build file to Sources build phase for the correct target (HealthApp for app files, HealthAppTests for test files)
- Use a script or Xcode's "Add Files" feature to ensure proper integration.

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

## Cursor Cloud specific instructions

This repository is an **iOS/Xcode** project. Cursor Cloud VMs are **Linux** and cannot run `xcodebuild`, the iOS Simulator, or the SwiftUI app binary. Use the VM for Swift edits, static analysis, and optional **Ollama** (default AI backend) smoke tests; run full builds/tests on a Mac with Xcode 15+.

### What works on Linux (this VM)

| Task | Command / notes |
|------|-----------------|
| SwiftLint (style/static checks) | `cd HealthApp && swiftlint lint` — expects `swiftlint` on `PATH` (default rules; repo has no `.swiftlint.yml`) |
| Ollama API (matches `OllamaClient` / port `11434`) | Start server, then call HTTP API (see below) |
| Personas prompts sanity | `ls Personas-Prompts/*.txt` — static `.txt` files bundled for chat personas |
| Git / docs / code review | Standard |

### What requires macOS

| Task | Command |
|------|---------|
| Build app | `cd HealthApp && xcodebuild -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` |
| Unit/UI tests | `xcodebuild test -scheme HealthApp -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` |
| SwiftPM resolve for app | Xcode first open / `xcodebuild -resolvePackageDependencies` on Mac |

### Ollama on the Cloud VM

The app defaults to `localhost:11434` (`ServerConfigurationConstants`). On Linux, run the server in **tmux** (long-lived):

```bash
SESSION_NAME="ollama-server"
tmux -f /exec-daemon/tmux.portal.conf has-session -t "=$SESSION_NAME" 2>/dev/null \
  || tmux -f /exec-daemon/tmux.portal.conf new-session -d -s "$SESSION_NAME" -- "${SHELL:-bash}" -l
tmux -f /exec-daemon/tmux.portal.conf send-keys -t "$SESSION_NAME:0.0" 'ollama serve' C-m
```

Smoke test (connection + chat), same API the app uses:

```bash
curl -s http://127.0.0.1:11434/api/tags
curl -s http://127.0.0.1:11434/api/chat -d '{"model":"tinyllama","messages":[{"role":"user","content":"Hello from BisonHealth AI setup"}],"stream":false}'
```

Pull a model once per VM if needed: `ollama pull tinyllama` (or `llama3.2` to match app default). **Docling** (`localhost:5001`) is optional — default document processing is on-device; no Docling container is defined in-repo.

### Mac + Linux VM workflow

Develop on Linux, run the app on a Mac Simulator/device. Point **Settings → Ollama** at `http://<cloud-vm-host>:11434` when testing AI against the VM-hosted Ollama instance.

### Tooling paths (VM image)

- Swift: `/opt/swift/usr/bin` (add to `PATH` in shell profile if missing)
- SwiftLint: `/usr/local/bin/swiftlint`
- Ollama: `ollama` / `ollama serve` (system install under `/usr/local`)
