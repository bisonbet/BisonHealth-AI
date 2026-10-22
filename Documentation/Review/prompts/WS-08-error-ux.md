# WS-08 — Error handling & failure UX

**Phase 1 · model tier: mid · output: `Documentation/Review/findings/WS-08-error-ux.md`**

Beta feedback is dominated by "it didn't work and I don't know why." This workstream
walks every failure the user can cause and judges what they see. You are reviewing the
*experience* of failure, not the correctness of the code path — WS-02/04/05 own that.

## Method

1. Inventory every error type in the app:

```bash
grep -rn ': Error\b\|: LocalizedError\|enum .*Error' HealthApp/HealthApp --include='*.swift'
grep -rn 'errorDescription\|recoverySuggestion\|failureReason' HealthApp/HealthApp --include='*.swift'
grep -rn 'catch' HealthApp/HealthApp --include='*.swift' | wc -l
```

2. For each error type, record: does it have a user-facing message, is that message
   written for a non-engineer, does it have a recovery suggestion, and does any case leak
   PHI or an internal identifier into the text?

3. Find every silent `catch`. A `catch { }` or `catch { AppLog.error(...) }` with no UI
   effect means the user's action appeared to do nothing. List each with the user action
   it belongs to. These are the highest-value findings in this workstream.

4. Walk these flows and state exactly what the user sees at each failure point. Read the
   code; you do not need to run the app, but if you can run it in the simulator, do, and
   say so.

   | Flow | Failure to check |
   |---|---|
   | First launch | database init fails, disclaimer declined, migration fails |
   | Add a blood test by hand | required field empty, implausible value, duplicate date |
   | Import a document | unsupported type, unreadable file, extraction finds nothing, out of disk |
   | Chat | no provider configured, bad credentials, endpoint unreachable, model not downloaded, context too large, mid-stream drop |
   | On-device model | insufficient memory, insufficient disk, download interrupted, corrupt download |
   | HealthKit | permission denied, permission revoked later, no data available |
   | Export / share | no data to export, write fails, user cancels the share sheet |
   | Appointment prep | no health data yet, generation fails mid-way |
   | Settings | invalid endpoint URL, credential test fails, switching provider mid-stream |

5. Check the global error presentation layer: is there one? If an alert's primary action
   is "Retry", does retry actually re-run the failed operation (prior finding P1-4 was a
   silent no-op)? Can two errors race and show only one? Does an error alert block a
   sheet that is already presented (a classic SwiftUI lost-alert bug)?

6. Check empty states versus error states. `ChatEmptyStateView` and
   `DocumentsEmptyStateView` exist — verify a *failure* to load never renders as "you
   have no data", which reads as data loss to the user.

7. Check destructive actions: delete document, delete conversation, clear all data, reset
   settings. Is there confirmation, is it reversible, and does the confirmation say what
   will actually be destroyed?

## Calibration

Rate severity by what the user concludes. "Spinner forever" and "looks like my data is
gone" are P1. "Message is technically worded" is P3. Don't rewrite copy wholesale; report
the cases where the message misleads, and propose replacement text only for those.

## Output

Plan §1.6 contract, plus the **flow × failure table** from step 4 filled in (with
file:line for each cell you verified), and a list of every silent `catch` with its user
action.
