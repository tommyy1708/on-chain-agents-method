#!/usr/bin/env bash
#
# check-transcription.sh — does the rework order account for every blocker in the review?
#
#   ./scripts/check-transcription.sh <review-reply> <rework-order>
#   ./scripts/check-transcription.sh --review-path <order>
#
# What it checks
#   The review reply declares its blockers in its front matter, and heads each one:
#                                            blockers: B1, B2      (or: blockers: none / 无)
#                                            ### B1 · <title>
#   The rework order accounts for each one:  - B1 → fix: …   /  - B2 → not fixing: <reason>
#                                            - B1 → 修:…     /  - B2 → 不修:<理由>
#   It fails (exit 1, one stderr line per problem) when a blocker is missing from the
#   order, when the order names a blocker the review never raised, when a number is
#   accounted for twice, when an entry is empty, when "not fixing" has no reason, or
#   when the entry is still a placeholder: not one letter, digit or Han character in it
#   (—, ?, ……, a zero-width space), or it contains one of the templates' placeholders
#   word for word. Pass: exit 0 and one summary line. Bad usage: exit 2.
#   It only checks that each blocker was accounted for, not how well: "待补充", "N/A" or
#   "TODO: 转写" pass. That is a known limit, decided by the human — a list of to-do
#   words is a guess, and guesses never end.
#
#   The review side: the "blockers:" line is authoritative, and the strict "### Bn · "
#   headings must be exactly the same set. The list may be separated by , ， 、 or
#   spaces. It fails when the front matter has no such line or it cannot be read, when
#   the list repeats or skips a number, when a listed blocker has no heading or a heading
#   is not listed, when a heading is repeated, and when a code fence is never closed.
#   Why a declared list and not a search for headings: guessing which lines were meant
#   as headings never ends — every round turned up a new spelling that got past, and
#   the wider the net, the more prose it caught. A declared list is read, not guessed.
#   The cross-check against the headings means a blocker is only dropped silently if
#   the list and its heading are both wrong.
#
#   --review-path reads the "review:" line from the front matter at the top of an order
#   and prints "none" or the path as written (relative to mailbox/). Exit 1 when there is
#   no front matter or no such line, when there are two, or when it is empty or still a
#   <…> placeholder. Every order must declare it, so the gate never depends on
#   recognising a line in the body.
#
# Why: the hub transcribes the review into the rework order by hand, and the one thing
# a hand transcription reliably does is drop a line. A dropped blocker is not rejected,
# not argued with — it just silently never gets fixed, and nobody downstream can tell,
# because the station only ever sees the order. So this runs where the order is sent:
# dispatch.sh calls it for every order that declares a review, and will not dispatch on
# a failure.
#
# Why code blocks are skipped: the templates themselves show the format inside ``` fences,
# and a review that quotes the format would otherwise raise a blocker called "example".
# Fences follow CommonMark, because a line that only looks like a fence (```` ``` ```` is
# inline code) would otherwise hide every blocker after it.

set -euo pipefail

die() { printf 'check-transcription: %s\n' "$1" >&2; exit 2; }

[ $# -eq 2 ] || die "usage: check-transcription.sh <review-reply> <rework-order> | --review-path <order>"
[ "$1" = "--review-path" ] || [ -f "$1" ] || die "no such file: $1"
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

REVIEW = re.compile(r"^review:(.*)$")
MANIFEST = re.compile(r"^blockers:\s*((?i:none)|无|B[0-9]+([\s,，、]+B[0-9]+)*)\s*$")
HEADING = re.compile(r"^### (B[0-9]+) · ")
ENTRY = re.compile(r"^- (B[0-9]+) → (修|不修|fix|not fixing)[:：](.*)$")
# The placeholders in templates/work-order*.md, word for word. An entry that contains one
# was not filled in, whatever was typed around it. Vec<T> or "<b>bold</b>" is real content.
TEMPLATE_PLACEHOLDERS = ("<转写后的要求>", "<理由;谁决定的>",
                         "<the requirement, as transcribed>", "<reason; who decided>")

def fail(message):
    print(f"check-transcription: {message}", file=sys.stderr)
    sys.exit(1)

if sys.argv[1] == "--review-path":
    lines = [l for l in front_matter(sys.argv[2]) if REVIEW.match(l)]
    if not lines:
        fail('order has no "review:" line in its front matter (write "review: none" if this is not a rework order)')
    if len(lines) > 1:
        fail('order has two "review:" lines')
    path = REVIEW.match(lines[0]).group(1).strip()
    if not path or re.match(r"^<[^<>]*>$", path):
        fail(f"order's review: line is not filled in: {lines[0]}")
    print("none" if path.lower() == "none" else path)
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
order_lines = lines_outside_fences(sys.argv[2], problems, "rework order")
for _, line in order_lines:
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
    if text and (not any(c.isalnum() for c in text) or any(p in text for p in TEMPLATE_PLACEHOLDERS)):
        problems.append(f"{b}: placeholder not filled")
    elif verb in ("不修", "not fixing"):
        not_fixing += 1
        if not text:
            problems.append(f"{b}: not fixing without a reason")
    else:
        fix += 1
        if not text:
            problems.append(f"{b}: empty entry")

def missing(b):
    """missing Bn — and if a line does mention Bn, which one, so nobody hunts for it."""
    mention = re.compile(rf"(?<![0-9A-Za-z]){b}(?![0-9A-Za-z])")
    n = next((n for n, line in order_lines if mention.search(line)), None)
    if n is None:
        return f"missing {b}"
    return f'missing {b} (line {n} mentions {b} but is not in the "- {b} → 修:…" format)'

problems = review_problems + [missing(b) for b in raised if b not in seen] + problems

if problems:
    for p in problems:
        print(f"check-transcription: {p}", file=sys.stderr)
    sys.exit(1)
print(f"check-transcription: ok · {len(raised)} blockers · {fix} fix · {not_fixing} not fixing")
PY
