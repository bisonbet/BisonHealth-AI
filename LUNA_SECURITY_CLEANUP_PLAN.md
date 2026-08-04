# BisonHealth-AI Security and Cleanup Plan for Luna

Repository: `/Users/champ/Sources/BisonHealth-AI`

This is an implementation and delegation plan for Luna 5.6 and its subagents. The goal is to improve security, privacy, cleanliness, and maintainability without risking existing encrypted data or turning cleanup into a broad rewrite.

## Objective

Complete these outcomes in order:

1. Harden secret-file exclusions.
2. Move AWS credentials from `UserDefaults` to Keychain with a safe migration.
3. Remove the broken plaintext offline-operation queue.
4. Prevent provider responses and PHI from leaking into persistent logs.
5. Enforce a safe provider endpoint URL policy.
6. Remove only proven dead or duplicate code.
7. Correct stale documentation and conflicting agent instructions.
8. Establish a practical SwiftLint policy and address only targeted crash risks.

## Mandatory safety rules

- Begin by reading `AGENTS.md` and this entire file.
- Start from a clean worktree and record the current branch and SHA.
- Preserve unrelated user changes.
- Do not modify anything under `legacy/`.
- Do not commit, push, open a pull request, rotate credentials, or change repository settings unless the user explicitly authorizes it.
- Never print credentials, API keys, health information, prompts, provider response bodies, or authorization headers.
- Never delete code merely because its name looks obsolete. Prove it is unused with `rg`, Xcode project inspection, and tests.
- Do not change the database-encryption Keychain service or account:
  - Service: `com.healthapp.encryption`
  - Account: `health_data_encryption_key`
- Do not delete `rawDoclingOutput`, its database columns, migrations, or recovery paths. These support legacy data.
- Do not invent a new encrypted offline queue during this cleanup.
- Do not attempt to fix every lint warning, force unwrap, TODO, or oversized file.
- Do not let two subagents edit the same file concurrently.
- If using parallel subagents, use isolated worktrees or branches. Otherwise perform packages sequentially.
- Every behavioral change needs focused tests.
- Every new Swift file must be added to `HealthApp/HealthApp.xcodeproj/project.pbxproj`.
- Stop and ask the user before making a product decision not covered by this plan.

## Coordinator workflow

Luna is the coordinator. Luna should:

1. Complete the preflight itself.
2. Create a file-ownership table before delegating.
3. Delegate one bounded work package per subagent.
4. Require each subagent to report evidence, tests, changed files, and unresolved risks.
5. Review every subagent diff before integration.
6. Integrate one package at a time and rerun focused validation.
7. Keep security fixes, functional removals, documentation, and lint cleanup in separate logical change groups.
8. Stop before committing or pushing unless the user separately authorizes those actions.

## Phase 0: Read-only preflight

Run from the repository root:

```bash
cd /Users/champ/Sources/BisonHealth-AI
git status --short
git branch --show-current
git rev-parse HEAD
git ls-files | rg '(^|/)\.env($|[.])'
git ls-files | rg -i '(secret|credential|token|private.?key)'
rg -n "AWSCredentialsManager|AWSCredentialsHelper|PendingOperationsManager|OpenAICompatibleClient|AIProviderFactory|RetryManager|rawDoclingOutput"
```

Also inspect:

- `.gitignore`
- `HealthApp/HealthApp.xcodeproj/project.pbxproj`
- Relevant unit and UI tests
- Whether `gitleaks` or another secret scanner is installed
- All call sites for files or symbols proposed for removal

If a real credential is found in tracked files or history:

1. Stop implementation.
2. Report the file and credential type without showing the secret.
3. Tell the user that provider-side rotation is required.
4. Do not assume deleting the file is sufficient.

Create a table with these columns before delegation:

| Package | Assigned agent | Files owned | Dependencies | Status |
|---|---|---|---|---|

No file may belong to two active subagents.

## Work package 1: Secret-file hygiene

Suggested owner: Subagent A.

### Scope

- `.gitignore`
- Existing security/setup documentation only if it discusses environment files

### Required changes

Expand `.gitignore` to cover common environment-file variants while allowing safe examples. Use a policy equivalent to:

```gitignore
.env
.env.*
*.env
.envrc
!.env.example
!*.env.example
```

Confirm that required committed configuration files are not accidentally ignored. Do not claim an API key leaked unless the scan finds one.

### Validation

Use `git check-ignore` to confirm:

- `.env`, `.env.local`, `.env.development`, `.env.test`, `.envrc`, and `service.env` are ignored.
- `.env.example` remains eligible for tracking.

Record GitHub secret scanning and push protection as repository-owner follow-ups if they cannot be verified locally.

### Acceptance criteria

- Common environment files are ignored.
- Safe example files remain trackable.
- No secrets appear in output or fixtures.

Suggested change-group title: `chore(security): harden environment file exclusions`

## Work package 2: Migrate AWS credentials to Keychain

Suggested owner: Subagent B. Assign only this package to that agent.

### Primary files

- `HealthApp/HealthApp/Services/AWSCredentialsManager.swift`
- `HealthApp/HealthApp/Services/AWSCredentialsHelper.swift`
- `HealthApp/HealthApp/Views/AWSBedrockSettingsView.swift`
- Relevant unit tests

### Current problem

AWS credentials are persisted in `UserDefaults`. A separate Keychain helper exists but is unused. Credentials are also copied into process environment variables with `setenv`.

### Required implementation

Create one authoritative credential-storage path using Keychain. Migration must follow this exact order:

1. Try to load credentials from Keychain.
2. If absent, inspect the legacy `UserDefaults` value.
3. Decode and validate the legacy value.
4. Save it to Keychain.
5. Read it back and verify the saved result.
6. Only after successful verification, delete the legacy `UserDefaults` value.
7. If Keychain storage or verification fails, preserve the legacy value and return a safe error.

Additional requirements:

- Remove `setenv` calls for AWS access key, secret key, and session token.
- Configure an appropriate `kSecAttrAccessible` value.
- Never log credential values.
- Deleting credentials must remove both current Keychain storage and the legacy `UserDefaults` copy.
- Empty or partially populated credentials must not be considered valid.
- The settings UI may claim secure storage only after the implementation actually uses Keychain.
- Use dependency injection or a storage protocol so failure paths can be tested without modifying the real user Keychain.

### Do not touch

Do not rename or alter the database-encryption Keychain service/account named in the safety rules.

### Required tests

- Save and load credentials.
- Migrate legacy `UserDefaults` credentials.
- Successful migration removes the legacy value.
- Failed Keychain save or verification preserves the legacy value.
- Deleting credentials removes both storage forms.
- Optional session-token behavior.
- No credentials are copied into process environment variables.

### Acceptance criteria

- AWS secrets are no longer stored in `UserDefaults`.
- AWS credentials are no longer placed in process environment variables.
- Migration cannot discard the only valid credential copy.
- Success and failure paths are tested.

Suggested change-group title: `fix(security): migrate AWS credentials to Keychain`

## Work package 3: Remove the broken plaintext offline queue

Suggested owner: Subagent C.

### Primary files

- `HealthApp/HealthApp/Networking/PendingOperationsManager.swift`
- `HealthApp/HealthApp/Managers/AIChatManager.swift`
- `HealthApp/HealthApp/Managers/DocumentManager.swift`
- `HealthApp/HealthApp/Views/OfflineIndicatorView.swift`
- Relevant tests and documentation

### Current problem

The pending-operation queue stores operations in plaintext `UserDefaults`, including chat messages, health context, model data, and system prompts. Its execution methods are not implemented and always fail, so it retains sensitive information without providing a working retry feature.

### Required implementation

Prefer removal over redesign:

1. Remove chat and document call sites that enqueue sensitive operations.
2. Remove or revise the offline indicator/count if it represents this queue.
3. Remove the plaintext persisted queue data.
4. Remove `PendingOperationsManager` if no legitimate call sites remain.
5. Update tests and documentation so the app does not promise automatic retries that do not work.

During migration, delete only the specific `UserDefaults` key used by this queue. Never clear all defaults.

If removal changes a user-visible workflow beyond eliminating a nonfunctional retry claim, report the exact behavior change before integration.

### Explicit non-goal

Do not build an encrypted retry queue. Record that as a separate future feature requiring a threat model, encryption design, expiration policy, retry/idempotency rules, user controls, and migration tests.

### Acceptance criteria

- Chat content and health context are no longer persisted in plaintext.
- The app does not show a pending-operation count for operations that cannot execute.
- No dangling queue call sites remain.
- Tests confirm safe offline behavior without PHI retention.

Suggested change-group title: `fix(privacy): remove nonfunctional plaintext retry queue`

## Work package 4A: Sanitize provider errors and logs

Suggested owner: Subagent D.

### Primary files

- `HealthApp/HealthApp/Services/OpenAICompatibleClient.swift`
- `HealthApp/HealthApp/Managers/AppLog.swift`
- Relevant unit tests

### Current problem

Provider error responses can enter `localizedDescription` and then persistent application logs. Provider bodies may contain prompts, health context, or other sensitive information.

### Required implementation

- Do not place raw response bodies in persistent error descriptions.
- Preserve safe diagnostics such as HTTP status, provider type, and a safe request identifier header.
- If retaining a provider error message, sanitize it and impose a strict maximum length.
- Never retain prompts, health context, authorization headers, full response bodies, or model output.
- Prefer structured safe error fields over regex-only redaction.
- Ensure exported logs use the sanitized representation.

### Required tests

Use synthetic PHI-shaped data, not real information. Verify that:

- Raw response bodies do not appear in `localizedDescription`.
- PHI-shaped content does not appear in persisted or exported logs.
- HTTP status remains visible.
- Authorization values are removed.
- Large provider errors are bounded.
- Malformed or non-JSON responses are handled safely.

### Acceptance criteria

- Logs retain status-level diagnostic value.
- Provider bodies, prompts, credentials, and PHI are not persisted.

Suggested change-group title: `fix(privacy): sanitize provider errors before logging`

## Work package 4B: Enforce safe provider endpoint URLs

Assign this to Subagent D after 4A, unless another agent can work without editing overlapping files.

### Primary files

- `HealthApp/HealthApp/Services/OpenAICompatibleClient.swift`
- `HealthApp/HealthApp/Managers/SettingsManager.swift`
- Provider settings UI
- Relevant tests

### Required policy

- Allow `https://` endpoints.
- Allow `http://` only for `localhost`, `127.0.0.1`, and `::1`.
- Reject malformed URLs, missing hosts, unsupported schemes, and embedded username/password credentials.
- Reject ordinary remote `http://` endpoints.
- Use one shared validator so settings validation and request construction agree.

Do not silently allow local-LAN HTTP addresses. If addresses such as `192.168.x.x` are a requirement, stop and ask the user for a product decision.

### Required tests

- Valid HTTPS URL.
- Valid IPv4 and IPv6 loopback HTTP URLs.
- Invalid public HTTP URL.
- Invalid scheme.
- Missing host.
- Embedded username/password.

### Acceptance criteria

- Invalid endpoints cannot be saved or used.
- The UI provides a clear explanation.
- Request construction enforces the same policy.

Suggested change-group title: `fix(security): enforce safe provider endpoint URLs`

## Work package 5: Remove proven dead and duplicate code

Suggested owner: Subagent E. Start only after security packages have stable diffs.

### Candidates

- `HealthApp/HealthApp/Views/BloodTestEntryView_WithTemp.swift`
- `HealthApp/HealthApp/Database/Keychain.swift`
- Obsolete provider/factory/retry code in `HealthApp/HealthApp/Services/AIProviderInterface.swift`
- Related obsolete tests in `HealthApp/HealthAppTests/ServiceClientTests.swift`
- Unused PDF export API in `HealthApp/HealthApp/Managers/HealthDataManager.swift`

### Required proof before each deletion

1. Search the symbol and filename with `rg`.
2. Inspect `project.pbxproj`.
3. Classify every reference as production, test, preview, migration, or comment.
4. Remove only after proving there is no required runtime or migration path.
5. Build after each logical deletion group.

### Expected outcomes

- Delete `BloodTestEntryView_WithTemp.swift` after confirming it is unreferenced and duplicates active implementations.
- Delete the unreferenced duplicate `Database/Keychain.swift`, carefully distinguishing same-named files.
- Remove obsolete OpenAI/Anthropic placeholder providers, factory code, and the legacy retry manager only after tracing every symbol.
- Preserve active provider protocols, response types, and test helpers.
- Update tests that merely assert obsolete factory types.
- If the `HealthDataManager` PDF API has no call sites and returns plain text instead of a PDF, remove it rather than inventing a PDF renderer.

If the PDF API is user-facing, stop and produce a separate implementation proposal.

### Do not delete

- `rawDoclingOutput`
- Database migrations
- Legacy extraction recovery
- Shared model or protocol types that remain in use
- Placeholder product models without complete call-graph proof

### Acceptance criteria

- Every deletion has recorded call-site evidence.
- The Xcode project has no dangling references.
- Production build and tests remain green.

Suggested change-group title: `refactor: remove obsolete duplicate implementations`

## Work package 6: Align documentation and repository rules

Suggested owner: Subagent F. Documentation-only, after behavior is final.

### Files

- `README.md`
- `AGENTS.md`
- `AGENT_CODEBASE_INSTRUCTIONS.md`
- `CLAUDE.md`
- Other directly affected documentation

### Required changes

- Describe native document extraction as the active implementation.
- Describe Docling only as historical or legacy compatibility where applicable.
- Remove contradictory claims that Docling is both optional and required.
- Remove references to nonexistent `DoclingClient.swift`.
- Use `iPhone 17 Pro` as the canonical simulator.
- Resolve the Xcode-project instruction conflict: new Swift files must be added to `project.pbxproj`, but unrelated project-file rewrites are prohibited.
- Remove brittle hard-coded source/test counts, or replace them with commands that calculate current values.
- Remove unsupported offline-retry claims if package 3 removes that behavior.
- Add this definition-of-done checklist to the agent guidance:

```text
Before finishing:
- Remove code made unused by this change.
- Remove commented-out implementation blocks introduced or exposed by this change.
- Merge newly duplicated helpers when behavior and ownership are identical.
- Verify no secrets or PHI were added to source, tests, fixtures, or logs.
- Run focused tests and inspect the final diff.
```

Do not claim the repository has no remaining dead code or security issues.

### Acceptance criteria

- Documentation matches current behavior.
- Agent instructions no longer conflict.
- Simulator guidance and generated counts cannot immediately drift.

Suggested change-group title: `docs: align setup and agent guidance with current implementation`

## Work package 7: SwiftLint and targeted crash-risk cleanup

Suggested owner: Subagent G. Keep this as the final, separate package.

### Scope restriction

The repository has substantial existing lint debt. Do not turn this package into a repository-wide rewrite.

### Required sequence

1. Record current SwiftLint totals.
2. Add or refine `.swiftlint.yml`.
3. Exclude `legacy/`, generated files, and build output.
4. Do not disable meaningful safety rules globally merely to reach zero.
5. If using a baseline, baseline only intentional existing debt.
6. Keep mechanical formatting separate from behavioral changes.
7. Inspect every automated diff.
8. Run `git diff --check`.
9. Build and test after formatting.

### Initial targeted issue

Address the forced `CGDataProvider(...)!` in `FileSystemManager.swift`. Address other force unwraps only when nil behavior is clear and testable.

Do not broadly rewrite `DocumentProcessor`, `AIChatManager`, or large SwiftUI view files. Propose oversized-file decomposition as later work.

### Acceptance criteria

- Lint behavior is reproducible.
- No new violations are introduced.
- Automated fixes do not change SwiftUI behavior.
- The diff remains small and reviewable.

Suggested change-group title: `chore(lint): establish maintainable SwiftLint policy`

## Integration order

Integrate in this order:

1. Read-only preflight
2. Secret-file hygiene
3. AWS credential migration
4. Plaintext offline-queue removal
5. Provider-error privacy
6. Endpoint URL validation
7. Dead-code removal
8. Documentation alignment
9. Lint and targeted crash cleanup
10. Full validation

Packages may be developed in isolated worktrees, but integrate one at a time and rerun focused validation after every integration.

## Required final validation

From the repository root:

```bash
cd /Users/champ/Sources/BisonHealth-AI
git status --short
git diff --check
git ls-files | rg '(^|/)\.env($|[.])'
rg -n 'setenv\("AWS_|PendingOperationsManager|BloodTestEntryView_WithTemp'
```

Run SwiftLint:

```bash
cd /Users/champ/Sources/BisonHealth-AI/HealthApp
swiftlint lint --no-cache
```

Build:

```bash
xcodebuild \
  -project HealthApp.xcodeproj \
  -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Test:

```bash
xcodebuild \
  -project HealthApp.xcodeproj \
  -scheme HealthApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

If the simulator is unavailable, report that separately. List available destinations before using a substitute. Do not describe tests as passing if only compilation or test discovery succeeded.

If `gitleaks` is installed, run:

```bash
gitleaks detect --source . --redact
```

Never paste actual secret values from scanner output.

## Subagent return format

Every subagent must return:

1. Package completed.
2. Files changed and deleted.
3. Evidence used to establish call sites or behavior.
4. Tests added or updated.
5. Exact validation commands and results.
6. Remaining risks or unresolved decisions.
7. Confirmation that it did not commit, push, modify `legacy/`, or expose secrets/PHI.

## Coordinator final report

Luna's final report must include:

1. Changes completed, grouped by package.
2. Files changed and deleted.
3. AWS credential migration behavior and failure safety.
4. Privacy-sensitive persistence removed.
5. Focused tests added.
6. Exact build, test, lint, and secret-scan results.
7. Remaining warnings and manual validation requirements.
8. Work intentionally deferred.
9. Confirmation that no commit, push, credential rotation, or repository-settings change occurred unless separately authorized.

## Stop conditions

Stop and ask the user before continuing if:

- A tracked or historical credential is discovered.
- A migration could make encrypted user data inaccessible.
- Removing a component changes a working user-visible feature rather than broken behavior.
- Supporting non-loopback HTTP requires a product decision.
- Tests reveal pre-existing failures that obscure the package result.
- Completing a package requires changes under `legacy/`.
- A subagent proposes a broad rewrite outside its assigned files.
