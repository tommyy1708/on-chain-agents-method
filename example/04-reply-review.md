---
status: ACKED
from: review
re: to-review/2026-01-05-digest-review.md
---

# Verdict: **one blocker**

The new code is correct. **The problem is older than this change, and this change makes it
load-bearing.**

## ⛔ Blocker — `never sends the digest twice` guards nothing

That test has existed for eleven months. Its name states the guarantee the whole feature
rests on. **It does not test it.**

### Reproduction

1. Copy the repository to a scratch directory.
2. **Delete the deduplication entirely** — not the key, the whole check.
3. Run the full suite.

```
815 passed, 0 failed
```

**The suite is green with the feature removed.** The three new tests are scoped to the new
code path; the legacy test builds its own fixture, sends once, and asserts the mailbox has
one message — it never triggers a retry, so a second send has no way to appear.

### Why it matters more now than yesterday

Yesterday it was a weak test next to a feature nobody had touched. Today the station's
reply, this review, and the ledger will all record that "sending twice is covered." **The
next person will believe it.** A hollow guard is worse than a missing one: a missing guard
gets noticed.

### Fix

Give the legacy test a retry, or delete it and let the new tests own the guarantee.
**Do not leave it named what it is named while asserting what it asserts.**

## Should-fix (not blocking)

The two new tests share one fixture builder; a change to that builder can weaken both at
once without either going red.

## Guardrail self-check

All knives swung in `/tmp/review-digest`. Original untouched, `git status` empty, HEAD
unchanged. No comments posted on the change. No contact with the station.
