---
status: ACKED
from: station-a
re: to-station-a/2026-01-05-digest-idempotency.md
scope: digest job + its tests only. Schedule, retry policy and transport untouched.
---

# Digest now sends once per recipient per week

**Bottom line**: done. 812 → 815 tests, all green. Change is open, not merged.

## 1. What changed

- `jobs/weekly_digest.*` — a `sent_digests` record is written **in the same transaction
  as the send**, keyed on (recipient, week). A second attempt for the same key is skipped.
- Placed at the send site, per the order — a crash halfway leaves the first half recorded.

## 2. Proof

| | |
|---|---|
| Tests | 812 → **815**, all green |
| Build | clean |
| Branch / commit | `fix/digest-idempotency` / `a1b2c3d` |
| Working tree | clean |

### Mutation checks

| Knife | Result | Exact failure message |
|---|---|---|
| Remove the (recipient, week) key, keep the record | 🔴 | `expected 0 sends on re-run, got 3` |
| Write the record *after* the send instead of with it | 🔴 | `crash between send and record re-sends on retry` |

Both restored; diff empty afterwards.

## 3. Not verified

Real transport behaviour under a provider-side timeout. The order put the transport out of
bounds, so this is untested rather than tested-and-fine.

## 4. Found but not done

There is already a test called `never sends the digest twice` in the legacy suite. **I did
not touch it** — it was green before my change and green after. I did not check what it
asserts; the order did not ask me to, and it was already passing.
