# WS-13 — App Store compliance & metadata

**Phase 3 · model tier: mid · output: `Documentation/Review/findings/WS-13-appstore-compliance.md`**

This workstream decides whether the submission gets rejected. Treat it as a
documentation-and-configuration audit, not a code review.

## Mandatory first step

**Fetch the current rules. Do not rely on your training data** — the App Review
Guidelines, the privacy-manifest requirements, and the required-reason API list all
change several times a year, and a stale answer here costs a rejection cycle. Use the web
tools available to you to retrieve:

- the App Review Guidelines (particularly the sections on health/medical apps, data
  collection and storage, downloaded content, minimum functionality, and medical
  disclaimers);
- Apple's current privacy-manifest documentation, including the required-reason API list
  and the list of SDKs that must ship a signature/manifest;
- the current App Store Connect requirements for app privacy answers, export compliance,
  and screenshot sizes.

Record the URL and retrieval date for every rule you cite. A finding that cites a rule
without a source is not actionable.

## Known gaps to confirm and specify

1. **No `PrivacyInfo.xcprivacy` exists anywhere in the project.** The app uses
   `UserDefaults` in ~60 places and reads file timestamps / disk space in the file-system
   and storage code, which are required-reason API categories. Determine exactly which
   required-reason APIs the app and its dependencies use, which reason codes apply, and
   write the complete manifest the project needs (as a proposed file body in your report —
   do not add it to the project; that is a Phase 5 fix).

2. **Third-party SDK manifests.** Dependencies are `aws-sdk-swift`, `SQLite.swift`,
   `mlx-swift-lm`, and `bisonbet/textual` (a first-party fork). For each: does it ship a
   privacy manifest, is it on Apple's list of SDKs requiring one, and does the fork need
   one authored? Note that a forked dependency is the maintainer's responsibility — i.e.
   yours.

3. **`ITSAppUsesNonExemptEncryption` is absent from `Info.plist`.** The app uses CryptoKit
   for data at rest and TLS for transport. Determine the correct declaration and whether
   the exemption applies, so the key can be set once instead of answering the question on
   every upload.

4. **`aps-environment = development` is in the entitlements** but push usage appears
   limited to one reference in `DocumentProcessor.swift`. Determine whether push is
   actually used; if not, the entitlement should go. If it is, a production submission
   needs the production environment and a configured APNs key.

5. **HealthKit.** Verify the usage strings match actual behaviour, that
   `com.apple.developer.healthkit.access` being an empty array is correct for what the app
   does, and what the review notes must say about why HealthKit is used. Confirm the app
   does not do anything the HealthKit guidelines prohibit (coordinate with WS-07 item 11).

6. **Medical disclaimers.** `FirstLaunchDisclaimerView`, `TermsOfServiceView`, and
   `PrivacyPolicyView` exist. Read all three. Assess against the current guidelines for
   health/medical apps: is the "not medical advice" position stated before the user can get
   AI output, is it visible in-session (not only at first launch), and does the AI ever
   produce something that reads as diagnosis or a treatment change? `CLAUDE.md` says the
   on-device rules forbid diagnosing and telling the user to change a medicine or dose —
   verify that constraint is present on the cloud paths too, and say what a reviewer who
   asks the AI "should I stop taking my blood pressure medication?" will see.

7. **App privacy answers.** Draft the complete set of App Store Connect privacy answers
   the code supports: data types collected (health, identifiers, usage), whether they
   leave the device (they do, if a cloud provider is configured — the answers must reflect
   the cloud case honestly), linkage to identity, and tracking (none). Flag any
   contradiction with `PrivacyPolicyView`.

8. **Assets and metadata inventory.** Check and report status for:
   - app icon: `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-BisonHealthAI-Pro`; confirm
     every required size is present, 1024×1024 has no alpha, and the unused
     `AppIcon-Doctor-Dark` set is either wired up deliberately or removed;
   - screenshots for every required device size (fetch the current list);
   - age rating questionnaire answers, including the medical/health questions;
   - support URL, marketing URL, and a **publicly reachable** privacy policy URL — an
     in-app-only policy does not satisfy App Store Connect;
   - app name, subtitle, keywords, promo text, description, and "What's New";
   - `LSApplicationCategoryType` is `healthcare-fitness` — confirm that is the intended
     primary category.

9. **Minimum functionality and the reviewer's path.** The app is useless until the user
   adds data or configures a provider. Write the reviewer walkthrough: what demo data or
   configuration must be provided, whether a cloud key can be supplied for review, and
   what happens if the reviewer tries the on-device model (see WS-12 item 14).

10. **iOS 26.0 deployment target.** Confirm this is deliberate. It narrows the addressable
    audience sharply and means every beta tester needs iOS 26. Report it as a business
    decision with its consequence, not as a defect.

11. **Account deletion.** The app has no accounts, so Apple's account-deletion requirement
    should not apply. Confirm there is genuinely no account or sign-in anywhere, and note
    that the app should still offer a complete local-data deletion path.

## Output

Plan §1.6 contract, plus:
- a **compliance checklist table**: item → requirement (with source URL + date) → current
  state → gap → severity;
- the **proposed `PrivacyInfo.xcprivacy` body** as a fenced XML block;
- the **draft App Store Connect privacy answers**;
- the **draft reviewer notes**.

Severity here means rejection likelihood: certain rejection = P0, likely = P1, possible
question from review = P2, cosmetic = P3.
