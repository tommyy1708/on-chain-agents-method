---
status: NEW
from: hub
needs: independent review
reply: to-hub/YYYY-MM-DD-<slug>.md
review: none
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

A review order always says `review: none`; what it reviews goes in the body.

## Reply

Give an explicit verdict: **ready to merge**, or **blockers** (listed one by one, each with **reproduction steps** and a location).

Number every blocker, each under its own third-level heading:

```
### B1 · <one-line title>
<location, reproduction steps, why it is a blocker>
```

- Numbering starts at B1 and runs consecutively — no gaps.
- **Only blockers are numbered.** Should-fix and nits are listed separately as before, with no B-prefixed numbers.
- Add one line to the reply's front matter, next to `status:` and `from:`. **Fill it in last, after every blocker is written** — a list filled in first is a count announced before the search:
  - blockers found: `blockers: B1, B2, B3` — exactly the `### Bn · ` headings in the body, no more, no fewer;
  - none: `blockers: none`, and no `### B` heading anywhere in the body.

  This line is what the rework order is checked against. A missing or unreadable line, or one that disagrees with the headings, stops the rework from being dispatched.
- Separate the list with half-width commas, full-width commas or 、 — `blockers: B1, B2`, `blockers: B1，B2` and `blockers: B1、B2` all read the same.
- A line that starts with `### B` is only ever a real blocker. To show an example, put it inside a code fence.
- When you are done, you can check yourself once: run `scripts/check-transcription.sh <this reply> <a draft rework order>`.

Keep should-fix and nits separate from blockers.
**Every finding must be falsifiable** — if you say something breaks, give the exact input that breaks it.
