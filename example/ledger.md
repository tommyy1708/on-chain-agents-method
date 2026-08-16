# The ledger at three moments

The ledger is not a task list. It is **the reasoning as it stood at the time.** These three
snapshots show the same entry accumulating that reasoning.

## Moment 1 — dispatched

```json
{
  "agents": {
    "station-a": {
      "state": "running",
      "task": "to-station-a/2026-01-05-digest-idempotency.md",
      "since": "2026-01-05 09:40",
      "log": ".shifts/20260105-094012-station-a-digest.log"
    },
    "review": { "state": "idle", "task": "", "since": "" }
  },
  "backlog": [
    "[dispatched · 2026-01-05 09:40] station-a ← digest idempotency. Boundaries: schedule, retry policy and transport untouched; open the change, do not merge. Acceptance: re-running immediately sends zero, and a test goes red if that stops being true."
  ]
}
```

## Moment 2 — reply is in, review dispatched

Note what the hub wrote down: **not "looks good" — what it refused to accept on trust.**

```json
{
  "backlog": [
    "[dispatched · 2026-01-05 11:05] review ← digest idempotency. Told it explicitly NOT to repeat the station's two knives (both test 'is the new guard wired up'), and pointed it at the one thing the station reported but did not open: a legacy test named 'never sends the digest twice'. A test whose name is a guarantee is where a hollow assertion hides.",
    "[accepted · 2026-01-05 11:00] station-a — digest idempotency. Ran the suite myself: 812 → 815 green. Read the diff line by line; schedule, retry policy and transport genuinely untouched. Station's two knives reproduced. NOT yet merge-ready: functional change, slow lane."
  ]
}
```

## Moment 3 — verdict in, rework dispatched

```json
{
  "pending_decision": [
    "[open · 2026-01-05 14:20] The eleven-month-old test named 'never sends the digest twice' asserts nothing — verified: deleting deduplication entirely leaves 815 passing. Options: (a) give it a retry, (b) delete it and let the new tests own the guarantee. Recommend (a): the name is load-bearing in three places now."
  ],
  "backlog": [
    "[dispatched · 2026-01-05 14:25] station-a ← rework. Transcribed the reviewer's finding into an order; station and reviewer never spoke. Required it to REPRODUCE the green-with-feature-deleted state before fixing anything — a fix applied without seeing the failure is a fix nobody can trust.",
    "[accepted · 2026-01-05 14:20] review — verdict: one blocker. Hub reproduced the blocker independently in its own scratch copy before transcribing it: deleted deduplication, ran full suite, 815 passed. Confirmed. Reviewer's guardrails checked: scratch directory only, original byte-identical."
  ]
}
```

## What to notice

- Every entry says **how it was checked**, not just what happened.
- The hub **reproduced the blocker itself** before passing it on. A verdict is a lead too.
- The station and the reviewer **never communicated.** The hub transcribed.
- The rework order requires **reproducing the failure before fixing it** — otherwise nobody
  can tell whether the fix worked or the problem was never there.
