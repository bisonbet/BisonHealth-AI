# WS-07 — PHI handling & security

**Phase 1 · model tier: strong · output: `Documentation/Review/findings/WS-07-phi-security.md`**

The app's entire value proposition is "your health data stays on your device." This
workstream verifies that claim is literally true, and that nothing in the repo, the
logs, the exports, or the network layer contradicts it. A finding here is a P0 by
default; argue it down if the exposure requires unusual steps.

## Scope

Whole repository, including tests, fixtures, and docs. The app is the primary target but
the repo itself is in scope for leaked secrets and real patient data.

## What to examine

**1. Logging.** `Managers/AppLog.swift` is ~900 LOC — read it fully. Determine:
- what is written where (OSLog, file, console), with what retention, in which build configs;
- whether `privacy:` interpolation levels are used correctly on every PHI-bearing log;
- whether any log line can carry a lab value, name, DOB, medication, document text,
  prompt, or model response in a release build (prior P0-2 was PHI in durable plaintext logs);
- whether log files are inside the app container, encrypted, and excluded from backup;
- whether logs are included in any share/export/diagnostic path.

```bash
grep -rn 'AppLog\|os_log\|Logger(' HealthApp/HealthApp --include='*.swift' | wc -l
grep -rn 'print(\|debugPrint\|NSLog' HealthApp/HealthApp --include='*.swift'
```

**2. Error messages.** An error string that embeds the failing payload leaks PHI into
alerts, logs, and crash reports. Check the error types' `localizedDescription` and any
`String(describing:)` of a model object.

**3. Exports and sharing.** `Utils/ConversationExporter.swift` (~700 LOC),
`Views/DataExportView.swift`, document share, appointment-prep output, PDF report. For
each: what exactly leaves the app, is it encrypted or plaintext, does the user know, and
does it respect the privacy toggles? Check temp files written for sharing are deleted
afterwards and are not world-readable within the container.

**4. Pasteboard.** Any PHI copied to the clipboard — is it marked
`UIPasteboard.OptionsKey.localOnly` / expiring where appropriate? Universal clipboard
sends it to the user's other devices, which contradicts "on-device only".

**5. Screenshots and the app switcher.** Does the app blur or hide PHI when backgrounded?
Not strictly required, but relevant to the privacy claim — report as P2/P3 with a
recommendation, not as a defect, if absent.

**6. Network egress inventory.** Build the complete list of hosts the app can contact and
what it sends to each: AWS Bedrock, user-configured OpenAI-compatible endpoints, the MLX
model download host (Hugging Face), and anything from the SPM dependencies. For each:
does it carry PHI, is it TLS, and is it disclosed in `PrivacyPolicyView`? Confirm there is
**no** analytics, telemetry, crash-reporting, or ad SDK sending anything.

```bash
grep -rnoE 'https?://[a-zA-Z0-9./_-]+' HealthApp/HealthApp --include='*.swift' | sort -u -t: -k3
```

**7. On-device vs cloud honesty.** The UI must make it unmistakable when a message is
going to a cloud provider versus staying on-device. Verify the indicator exists, is
correct for all three providers, and cannot be stale after a provider switch mid-session.

**8. Keychain and secrets.** Accessibility classes, `kSecAttrSynchronizable` (iCloud
Keychain sync would move credentials off-device), and whether any credential is in
`UserDefaults`. Then scan the repo for committed secrets:

```bash
git log --all --diff-filter=A --name-only | grep -iE '\.(p12|p8|pem|key|env|sqlite)$' | sort -u
grep -rnE 'AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}|aws_secret' . --include='*' 2>/dev/null | grep -v '^./.git/'
```

**9. Real patient data in the repo.** Check `HealthAppTests` fixtures, `Personas-Prompts/`,
and any sample documents for anything that looks like a real person's records. Report
immediately as P0 if found.

**10. Backup and iCloud.** `CLAUDE.md` says iCloud/CloudKit backup was removed because no
BAA is available. Verify: no CloudKit entitlement, no `NSUbiquitousContainers`, and that
the DB, documents, logs, and model files have the intended `isExcludedFromBackup`
posture. Note that excluding everything means a device restore loses all health data —
check whether the user is told that, and whether a local export path exists as mitigation.

**11. HealthKit.** Data read from HealthKit must not be written anywhere Apple forbids
(iCloud, advertising, or third parties). Verify what is read, where it is stored, and
whether it is sent to cloud AI providers — and whether the user is told that it is.

**12. Claims audit.** Read `README.md` §Privacy & Security, `PrivacyPolicyView`, and
`TermsOfServiceView`. Flag every statement the code does not support. An inaccurate
privacy claim is both an App Store problem and a trust problem.

## Output

Plan §1.6 contract, plus a **data egress table** (destination → payload → PHI? → TLS? →
disclosed where?) and a **PHI-at-rest table** (store → encrypted? → backed up? → purged when?).
