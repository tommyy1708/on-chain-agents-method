---
status: NEW
from: hub
needs: independent review
reply: to-hub/YYYY-MM-DD-<slug>.md
---

# Review: <change identifier>

**Where**: <branch / commit / scope of the diff>
**Automated checks**: <current state. If they have not finished, say so.>

## What the change is

<Two or three sentences, so the reviewer does not have to infer intent.>

## Deliberately out of scope

<What the dispatcher or the human decided not to do, **with the reason.**>
**These are not defects — do not report them as blockers.** But if this change makes one of them **worse**, report that.

## Already done — do not repeat

- <checks already run>
- <knives already swung, with results>

⇒ **Your value is in a different angle.** The same knife swung twice is one knife.

## Attack these first

1. **<Highest priority>** — <why it is the most likely to break. If it holds, it is a blocker.>
2. Are any assertions **vacuous** — conditions that can never hold, or assertions against an intermediate value rather than what is actually emitted?
3. <Knock-on effects specific to this change.>

## Guardrails

- **Zero write access to what you review.** No edits, no commits, no pushes, no comments on the change.
  To swing a knife, **copy to a scratch directory and swing it there**; the original stays byte-identical, and you prove it at the end.
- No direct channel to the author. The verdict goes to the hub, which transcribes it.
- <Extra prohibitions for this order: external calls / real messages / databases.>

## Reply

Give an explicit verdict: **ready to merge**, or **blockers** (listed one by one, each with **reproduction steps** and a location).
Keep should-fix and nits separate from blockers.
**Every finding must be falsifiable** — if you say something breaks, give the exact input that breaks it.
