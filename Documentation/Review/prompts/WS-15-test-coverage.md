# WS-15 — Test suite quality & coverage gaps

**Phase 3 · model tier: mid · output: `Documentation/Review/findings/WS-15-test-coverage.md`**

23 test files / ~7,400 LOC against 124 source files / ~51,800 LOC. Some of that ratio is
fine (views need UI tests, not unit tests), but the distribution is suspicious:
`DatabaseTests.swift` is 62 lines for an encrypted database with 12 migrations, and
`HealthDataManagerTests.swift` is 38 lines for the primary data manager.

Your job is to say where the suite gives false confidence, and to specify the tests that
would have caught the prior review's P0/P1 findings.

## Audit

1. **Inventory.** For each test file: LOC, number of test methods, what it actually
   asserts, and whether it tests behaviour or restates the implementation. Flag tests
   that cannot fail (no assertions, assertions on constants, `XCTAssertNotNil` on a
   non-optional).
2. **Coverage by risk, not by line count.** Map the suite against the app's risk areas:
   migrations, encryption, document pipeline state machine, provider error paths,
   streaming, privacy toggles, context assembly, cancellation. For each area state:
   covered / partially covered / not covered, with the test names as evidence. Line
   coverage numbers are welcome if you can generate them
   (`xcodebuild test -enableCodeCoverage YES` then `xcrun xccov`), but the risk map is
   the deliverable.
3. **Regression tests for prior findings.** `PreBetaRegressionTests.swift` (~390 LOC) and
   `AIChatManagerReliabilityTests.swift` (~60 LOC) exist. Cross-reference against the 2
   P0s and 15 P1s in `PRE-BETA-REVIEW.md`: which have a test that would fail if the fix
   were reverted? Produce that table. Any P0/P1 without such a test is a finding — those
   are exactly the fixes most likely to regress silently (see WS-01).
4. **Migration tests.** Is there any test that builds a v1..v11 database and migrates it
   to 12? If not, that is the single highest-value missing test in the project. Specify how
   to write it: fixture databases, or programmatic construction of each old schema.
5. **UI test reliability.** 7 UI test files. Identify: hardcoded sleeps, reliance on
   English strings instead of accessibility identifiers, dependence on pre-existing data or
   test order, and anything that will break on iPad or at large text sizes. Run the UI
   suite twice and report any result that changed.
6. **Test data hygiene.** Confirm no fixture contains real patient data (coordinate with
   WS-07 item 9) and that tests do not write into the real app container or leave state
   that affects the next run.
7. **Determinism.** Tests that depend on the current date, timezone, locale, network, or a
   configured AI provider. Any test that hits a real network endpoint is a finding.
8. **Missing test infrastructure.** Are there fakes/mocks for `DatabaseManager`, the three
   AI clients, and the file system? If every test needs the real thing, that explains the
   thin coverage — propose the minimum seam set that would unblock unit testing, naming the
   protocols that already exist (`AIProviderInterface`, `HealthDataProtocol`) and the ones
   that would need to be introduced.

## Deliverable: the test backlog

A prioritised list of tests to write, each with: the risk it covers, the file it belongs
in, the setup it needs, and whether it is unit or UI. Cap it at 25 and order it so the
first five are the ones to write before the beta goes out.

## Constraints

Do not write the tests. Do not modify existing tests. This workstream produces the plan;
Phase 5 writes the code.

## Output

Plan §1.6 contract, plus the **risk coverage map**, the **prior-findings regression test
table**, and the **test backlog**. Findings here are about false confidence and missing
coverage; severity is at most P1 (a missing migration test before a beta that migrates
real user data is defensible as P1 — be prepared to argue it).
