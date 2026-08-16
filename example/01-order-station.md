---
status: ACKED
from: hub
needs: authorised — execute this shift
reply: to-hub/2026-01-05-digest-idempotency.md
---

# Make the weekly digest send exactly once

## Where this came from

Two users received the digest twice on 2026-01-03. The job runs on a schedule and is
retried on failure; a retry after a partial success re-sends.

## What is wanted

A retried run must not re-send to a recipient who already received this week's digest.

**Done means:** re-running the job immediately after a successful run sends zero emails,
and a test fails if that stops being true.

## How

1. Read `jobs/weekly_digest.*` and the tests that already cover it. **Report what is
   already there before adding anything** — there may be a guard already.
2. Add the deduplication at the point of send, not at the top of the job: a crash halfway
   through must not re-send the first half.
3. Add the test. Then **break the deduplication on purpose and confirm the test goes red.**

## ⛔ Out of bounds

- Do not change the schedule or the retry policy.
- Do not touch the mail transport.
- Do not merge. Open the change and stop.

## How it will be proven

- The diff
- Test counts before and after
- **Every mutation check: what was broken, red or green, and the exact failure message**
- Branch / commit / clean tree
