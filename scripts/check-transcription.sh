#!/usr/bin/env bash
#
# check-transcription.sh — does the rework order account for every blocker in the review?
#
#   ./scripts/check-transcription.sh <review-reply> <rework-order>
#
# What it checks
#   The review reply numbers its blockers:   ### B1 · <title>
#   The rework order accounts for each one:  - B1 → fix: …   /  - B2 → not fixing: <reason>
#                                            - B1 → 修:…     /  - B2 → 不修:<理由>
#   It fails (exit 1, one stderr line per problem) when a blocker is missing from the
#   order, when the order names a blocker the review never raised, when a number is
#   accounted for twice, when an entry is empty, when "not fixing" has no reason, or
#   when the entry is still a placeholder (<…>, … or ...). Pass: exit 0 and one summary
#   line. Bad usage: exit 2.
#
#   The review side fails closed too. It fails when a line looks like a blocker heading
#   but is not exactly "### Bn · " (### B3·, ### B3 —, #### B3 ·, ### **B3** ·), when a
#   number is raised twice or skipped, when there is no heading at all and the review
#   does not say "无 blocker" / "no blockers", and when a code fence is never closed.
#   Why both sides: the order can only be checked against what was read out of the
#   review. A blocker the reader silently drops is one the order is never asked for —
#   exit 0, a plausible count, and the gate is empty. A strict reader is only safe if
#   anything it cannot read is an error, not a skip.
#
# Why: the hub transcribes the review into the rework order by hand, and the one thing
# a hand transcription reliably does is drop a line. A dropped blocker is not rejected,
# not argued with — it just silently never gets fixed, and nobody downstream can tell,
# because the station only ever sees the order. So this runs where the order is sent:
# dispatch.sh --from-review calls it and will not dispatch on a failure.
#
# Why code blocks are skipped: the templates themselves show the format inside ``` fences,
# and a review that quotes the format would otherwise raise a blocker called "example".
# Fences follow CommonMark, because a line that only looks like a fence (```` ``` ```` is
# inline code) would otherwise hide every blocker after it.

set -euo pipefail

die() { printf 'check-transcription: %s\n' "$1" >&2; exit 2; }

[ $# -eq 2 ] || die "usage: check-transcription.sh <review-reply> <rework-order>"
[ -f "$1" ]  || die "no such file: $1"
[ -f "$2" ]  || die "no such file: $2"

python3 - "$1" "$2" <<'PY'
import re, sys

# CommonMark fences: 0-3 spaces, then ≥3 backticks or ≥3 tildes. A backtick "fence" whose
# rest of line holds another backtick is inline code, not a fence.
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")

def lines_outside_fences(path, problems):
    """(line number, line) for each line outside a code fence."""
    out, fence, opened = [], None, 0
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\r\n")
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            fence, opened = m.group(1), n
            continue
        out.append((n, line))
    if fence:
        problems.append(f"unclosed code fence opened at line {opened}")
    return out

HEADING = re.compile(r"^### (B[0-9]+) · ")
# Anything a writer could have meant as a blocker heading: ###B3, #### B3, ### **B3**, **B3** …
HEADING_LIKE = re.compile(r"^\s{0,3}(#{1,6}\s*|\*\*\s*)\**\s*B[0-9]+(?![0-9])")
ENTRY = re.compile(r"^- (B[0-9]+) → (修|不修|fix|not fixing)[:：](.*)$")
# The whole entry is one <…>, or a bare … / ..., and nothing else. Vec<T> or "<b>bold</b>"
# is real content.
PLACEHOLDER = re.compile(r"^(<[^<>]*>|…|\.\.\.)$")

review_problems, raised, says_none = [], [], False
for n, line in lines_outside_fences(sys.argv[1], review_problems):
    m = HEADING.match(line)
    if m:
        b = m.group(1)
        if b in raised:
            if f"{b} raised twice in the review reply" not in review_problems:
                review_problems.append(f"{b} raised twice in the review reply")
        else:
            raised.append(b)
    elif HEADING_LIKE.match(line):
        review_problems.append(f'malformed blocker heading at line {n}: {line} (expected "### Bn · <title>")')
    if "无 blocker" in line or "no blockers" in line.lower():
        says_none = True

numbers = {int(b[1:]) for b in raised}
for i in range(1, max(numbers, default=0) + 1):
    if i not in numbers:
        review_problems.append(f"review reply skips B{i} (numbering must run B1, B2, … without gaps)")
if not raised and not says_none:
    review_problems.append('review reply numbers no blockers and does not say "无 blocker" / "no blockers"')

problems, seen, fix, not_fixing = [], set(), 0, 0
for _, line in lines_outside_fences(sys.argv[2], problems):
    m = ENTRY.match(line)
    if not m:
        continue
    b, verb, text = m.group(1), m.group(2), m.group(3).strip()
    if b in seen:
        if f"{b} appears twice" not in problems:
            problems.append(f"{b} appears twice")
        continue
    seen.add(b)
    if b not in raised:
        problems.append(f"unknown {b} (not in the review reply)")
    if PLACEHOLDER.match(text):
        problems.append(f"{b}: placeholder not filled")
    elif verb in ("不修", "not fixing"):
        not_fixing += 1
        if not text:
            problems.append(f"{b}: not fixing without a reason")
    else:
        fix += 1
        if not text:
            problems.append(f"{b}: empty entry")

problems = review_problems + [f"missing {b}" for b in raised if b not in seen] + problems

if problems:
    for p in problems:
        print(f"check-transcription: {p}", file=sys.stderr)
    sys.exit(1)
print(f"check-transcription: ok · {len(raised)} blockers · {fix} fix · {not_fixing} not fixing")
PY
