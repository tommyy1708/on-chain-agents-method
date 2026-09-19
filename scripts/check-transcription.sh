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
#   accounted for twice, when "not fixing" has no reason, or when the entry is still
#   the template's <…> placeholder. Pass: exit 0 and one summary line. Bad usage: exit 2.
#
# Why: the hub transcribes the review into the rework order by hand, and the one thing
# a hand transcription reliably does is drop a line. A dropped blocker is not rejected,
# not argued with — it just silently never gets fixed, and nobody downstream can tell,
# because the station only ever sees the order. So this runs where the order is sent:
# dispatch.sh --from-review calls it and will not dispatch on a failure.
#
# Why code blocks are skipped: the templates themselves show the format inside ``` fences,
# and a review that quotes the format would otherwise raise a blocker called "example".

set -euo pipefail

die() { printf 'check-transcription: %s\n' "$1" >&2; exit 2; }

[ $# -eq 2 ] || die "usage: check-transcription.sh <review-reply> <rework-order>"
[ -f "$1" ]  || die "no such file: $1"
[ -f "$2" ]  || die "no such file: $2"

python3 - "$1" "$2" <<'PY'
import re, sys

def lines_outside_fences(path):
    fenced = False
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\r\n")
        if line.lstrip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            yield line

HEADING = re.compile(r"^### (B[0-9]+) · ")
ENTRY = re.compile(r"^- (B[0-9]+) → (修|不修|fix|not fixing)[:：](.*)$")
# The whole entry is one <…> and nothing else. Vec<T> or "<b>bold</b>" is real content.
PLACEHOLDER = re.compile(r"^<[^<>]*>$")

raised = []
for line in lines_outside_fences(sys.argv[1]):
    m = HEADING.match(line)
    if m and m.group(1) not in raised:
        raised.append(m.group(1))

problems, seen, fix, not_fixing = [], set(), 0, 0
for line in lines_outside_fences(sys.argv[2]):
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

problems = [f"missing {b}" for b in raised if b not in seen] + problems

if problems:
    for p in problems:
        print(f"check-transcription: {p}", file=sys.stderr)
    sys.exit(1)
print(f"check-transcription: ok · {len(raised)} blockers · {fix} fix · {not_fixing} not fixing")
PY
