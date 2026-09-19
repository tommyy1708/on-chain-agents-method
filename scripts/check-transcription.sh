#!/usr/bin/env bash
#
# check-transcription.sh — does the rework order account for every blocker in the review?
#
#   ./scripts/check-transcription.sh <review-reply> <rework-order>
#   ./scripts/check-transcription.sh --source <order>
#
# What it checks
#   The review reply declares its blockers in its front matter, and heads each one:
#                                            blockers: B1, B2      (or: blockers: none)
#                                            ### B1 · <title>
#   The rework order accounts for each one:  - B1 → fix: …   /  - B2 → not fixing: <reason>
#                                            - B1 → 修:…     /  - B2 → 不修:<理由>
#   It fails (exit 1, one stderr line per problem) when a blocker is missing from the
#   order, when the order names a blocker the review never raised, when a number is
#   accounted for twice, when an entry is empty, when "not fixing" has no reason, or
#   when the entry is still a placeholder (<…>, only dots or ellipses, TBD, TODO, 待补,
#   待定). Pass: exit 0 and one summary line. Bad usage: exit 2.
#
#   The review side: the "blockers:" line is authoritative, and the strict "### Bn · "
#   headings must be exactly the same set. It fails when the front matter has no such
#   line or it cannot be read, when the list repeats or skips a number, when a listed
#   blocker has no heading or a heading is not listed, when a heading is repeated, and
#   when a code fence is never closed.
#   Why a declared list and not a search for headings: guessing which lines were meant
#   as headings never ends — every round turned up a new spelling that got past, and
#   the wider the net, the more prose it caught. A declared list is read, not guessed.
#   The cross-check against the headings means a blocker is only dropped silently if
#   the list and its heading are both wrong.
#
#   --source prints the "来源:" / "Source:" path of an order (outside code fences), or
#   nothing if it has none. Exit 1 if the line is there but empty or a <…> placeholder.
#   dispatch.sh uses it to refuse a sourced order dispatched without --from-review.
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

[ $# -eq 2 ] || die "usage: check-transcription.sh <review-reply> <rework-order> | --source <order>"
[ "$1" = "--source" ] || [ -f "$1" ] || die "no such file: $1"
[ -f "$2" ] || die "no such file: $2"

python3 - "$1" "$2" <<'PY'
import re, sys

# CommonMark fences: 0-3 spaces, then ≥3 backticks or ≥3 tildes. A backtick "fence" whose
# rest of line holds another backtick is inline code, not a fence.
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")

def lines_outside_fences(path, problems, what):
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
        problems.append(f"unclosed code fence in {what}, opened at line {opened}")
    return out

def front_matter(path):
    """The lines between a first-line --- and the next ---. None at all without both."""
    lines = open(path, encoding="utf-8").read().splitlines()
    if not lines or lines[0].rstrip() != "---":
        return []
    for i in range(1, len(lines)):
        if lines[i].rstrip() == "---":
            return lines[1:i]
    return []

SOURCE = re.compile(r"^(来源|Source)\s*[:：]\s*(.*)$")
MANIFEST = re.compile(r"^blockers:\s*((?i:none)|B[0-9]+([\s,]+B[0-9]+)*)\s*$")
HEADING = re.compile(r"^### (B[0-9]+) · ")
ENTRY = re.compile(r"^- (B[0-9]+) → (修|不修|fix|not fixing)[:：](.*)$")
# The whole entry is one <…>, or only dots and ellipses (… …… ...), or a to-do word, and
# nothing else. Vec<T> or "<b>bold</b>" is real content.
PLACEHOLDER = re.compile(r"^(<[^<>]*>|[.…]+|(?i:tbd|todo)|待补|待定)$")

if sys.argv[1] == "--source":
    for _, line in lines_outside_fences(sys.argv[2], [], "order"):
        m = SOURCE.match(line)
        if m:
            path = m.group(2).strip()
            if not path or re.match(r"^<[^<>]*>$", path):
                print(f"check-transcription: review source line is not filled in: {line}", file=sys.stderr)
                sys.exit(1)
            print(path)
            break
    sys.exit(0)

review_problems, listed = [], None
manifest = next((l for l in front_matter(sys.argv[1]) if l.startswith("blockers:")), None)
if manifest is None:
    review_problems.append('review reply has no "blockers:" line in its front matter')
elif not MANIFEST.match(manifest):
    review_problems.append(f"review reply blockers line unreadable: {manifest}")
else:
    listed = re.findall(r"B[0-9]+", manifest)
    for b in dict.fromkeys(listed):
        if listed.count(b) > 1:
            review_problems.append(f"{b} listed twice in blockers:")
    numbers = {int(b[1:]) for b in listed}
    for i in range(1, max(numbers, default=0) + 1):
        if i not in numbers:
            review_problems.append(f"blockers: skips B{i}")

headings = []
for _, line in lines_outside_fences(sys.argv[1], review_problems, "review reply"):
    m = HEADING.match(line)
    if m:
        b = m.group(1)
        if b in headings:
            if f"{b} raised twice in the review reply" not in review_problems:
                review_problems.append(f"{b} raised twice in the review reply")
        else:
            headings.append(b)

# What the order has to account for is the declared list — nothing read out of the body.
raised = list(dict.fromkeys(listed or []))
if listed is not None:
    for b in raised:
        if b not in headings:
            review_problems.append(f'{b} is in blockers: but has no "### {b} · " heading')
    for b in headings:
        if b not in raised:
            review_problems.append(f'{b} has a "### {b} · " heading but is not in blockers:')

problems, seen, fix, not_fixing = [], set(), 0, 0
for _, line in lines_outside_fences(sys.argv[2], problems, "rework order"):
    m = ENTRY.match(line)
    if not m:
        continue
    b, verb, text = m.group(1), m.group(2), m.group(3).strip()
    if b in seen:
        if f"{b} appears twice" not in problems:
            problems.append(f"{b} appears twice")
        continue
    seen.add(b)
    if listed is not None and b not in raised:
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
