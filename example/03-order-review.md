---
status: ACKED
from: hub
needs: independent review
reply: to-hub/2026-01-05-digest-verdict.md
---

# Review: digest idempotency

**Where**: `fix/digest-idempotency` / `a1b2c3d` / 3 files
**Automated checks**: all green

## What the change is

A retried digest run must not re-send. Deduplication is written in the same transaction as
the send, keyed on (recipient, week).

## Deliberately out of scope

Schedule, retry policy and mail transport. **Not defects. Do not report them as blockers.**

## Already done — do not repeat

The station swung two knives, both red:
- removing the (recipient, week) key
- writing the record after the send instead of with it

⇒ **Both test "is the new guard wired up." Take a different angle.**

## Attack these first

1. **The station reported an existing test named `never sends the digest twice`, and did
   not look inside it.** Look inside it. A test whose name is a guarantee is exactly where
   a hollow assertion hides.
2. Vacuous assertions anywhere in the three new tests.
3. Ordering: is there a path where the record is written and the send never happens?

## Guardrails

- Zero write access. Copy to a scratch directory to swing knives; original stays
  byte-identical and you prove it at the end.
- No channel to the station. Verdict goes to the hub.
