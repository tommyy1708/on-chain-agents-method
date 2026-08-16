# A worked example

One order, start to finish: dispatch → work → artifacts → independent review → rework → acceptance.

The task is deliberately ordinary. **The point of the example is what the review finds.**

| File | What it is |
|---|---|
| [`01-order-station.md`](01-order-station.md) | The hub's work order |
| [`02-reply-station.md`](02-reply-station.md) | What came back, with artifacts |
| [`03-order-review.md`](03-order-review.md) | The review order (note what it refuses to repeat) |
| [`04-reply-review.md`](04-reply-review.md) | The verdict — **this is the file to read** |
| [`05-order-rework.md`](05-order-rework.md) | Back around the loop |
| [`ledger.md`](ledger.md) | The ledger at three moments |

## The story in four lines

1. A weekly digest job sometimes sends twice. The station is asked to make the send idempotent.
2. It does. **Everything passes.** The reply is honest, complete, and correct.
3. The reviewer swings one knife the station did not: it **deletes the deduplication entirely** — and the suite stays green.
4. So the test named `never sends the digest twice` **was never guarding anything.** Neither the station nor the hub would have found this by reading reports.

## Why this is the example

Nothing here is exotic. There is no bad actor, no incompetent agent, no bug in the new code.

**The new code is correct.** What was wrong was already in the repository, wearing the name of a guarantee — and every automated check agreed with it.

That is the failure this whole model exists to catch, and it is invisible from a summary.
