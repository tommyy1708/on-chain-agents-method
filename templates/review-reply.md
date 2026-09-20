---
status: NEW
from: review
re: to-review/YYYY-MM-DD-<slug>.md
blockers: B1, B2
---

# Verdict: **2 blockers**

<One line, before anything else: **ready to merge**, or **N blockers**. The heading says the
same thing — a reader who stops at the heading must not get a different answer.>

## Blocker

<One `### Bn · ` heading per blocker, numbered from B1, consecutive, no gaps. Nothing else
in the reply gets a B number. **Fill in `blockers:` last, after every blocker is written** —
a list written first is a count announced before the search.>

### B1 · <one-line title>

**Where**: `path/to/file:line`
**Evidence**: <what you ran, and what it printed. An assertion without an artifact is not a
blocker — it is an opinion.>
**Suggested fix**: <what would make it right. The author may choose another way; say what
the guarantee has to be, not only how to spell it.>

### B2 · <one-line title>

**Where**: `path/to/file:line`
**Evidence**: <verbatim>
**Suggested fix**: <…>

## Should-fix

<Should change, but does not block the merge. **No B numbers here** — a number means the
merge stops, and nothing else may claim one.>

- <finding, with a location>

## Not verified

<What you could not check. Commands you did not run, branches you did not check out,
conclusions you reached by reading the code rather than by running it.

**Name the method, not just the conclusion.** "Merge conflicts: I could not test this, it is
inference, not measurement" is worth more than any verdict — the hub can go and measure it.

**Never present reasoning as measurement.** If this section is empty, say what you ran that
makes it empty.>

## Guardrail self-check

<Answer each prohibition in the review order, with the actual end state.

- Where the knives were swung (scratch directory), and that the original is byte-identical.
- No writes, no commits, no pushes, no comments on the change under review.
- No contact with the station; the verdict goes to the hub.>

---

> **This reply has no "found but not done" section, on purpose.** That section exists to
> catch work a station could not take on. **Review does not touch anything, so it has no
> undone work** — the honest equivalent is "Not verified" above.
>
> Two spellings the gate reads literally (`scripts/check-transcription.sh`):
> - `blockers: B1, B2` — separated by `,` `，` or `、`; or `blockers: none` when there are
>   none, and then **no `### B` heading anywhere in the body**.
> - `### B1 · <title>` — `###`, a space, `Bn`, a space, `·` (U+00B7), a space, the title.
>   The set of headings must equal the `blockers:` list exactly.
>
> A line starting with `### B` is always a real blocker. To show the format as an example,
> put it in a code fence. Check yourself before sending:
> `scripts/check-transcription.sh <this reply> <a draft rework order>`.
