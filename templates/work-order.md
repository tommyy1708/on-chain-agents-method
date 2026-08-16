---
status: NEW
from: hub
needs: <what this order asks of the station; if already authorised, say "authorised — execute this shift">
reply: to-hub/YYYY-MM-DD-<slug>.md
---

# <One line: what is being built>

## Where this came from

<Background. Why now, who decided the thing upstream, which earlier conclusions can be reused as-is.>

**Already done — do not repeat:** <path + one line.>

## What is wanted

<The goal, and **what counts as done**. The criterion must be falsifiable — "make it good" is not one; "changing X must turn Y red" is.>

## How (the plan)

1. <First>
2. <Then>
3. **On failure:** <what to do when something cannot be fetched, does not run, or contradicts the assumption — say explicitly: report it as it is, do not guess.>

> Deciding "how" is the dispatcher's job. **What arrives at the station should be a plan, not a puzzle.**

## ⛔ Out of bounds (crossing means redoing the work)

- <boundary>
- <boundary>
- Do not use <tools this order has no business with>
- Do not <irreversible action: merge / deploy / publish / force push>

**If you think a boundary should change**: write it under "found but not done" in your reply. **Do not act on it.**

## How it will be proven (artifacts to attach)

- <what changed and where>
- <check/test results, before and after>
- <mutation checks: each knife, red/green, and the **exact failure message**>
- <version control: branch / commit / clean tree>

## Reply

`to-hub/YYYY-MM-DD-<slug>.md`, `status: NEW / from: <you>`.
The last section must be **"found but not done."**
