#!/usr/bin/env bash
#
# accept.sh — close out a shift, and record how it was verified. One action, not two.
#
#   ./scripts/accept.sh <station> --note "<what you accepted, and how you checked it>"
#   ./scripts/accept.sh <station> --note "…" --reopen "<what still has to happen>"
#
# The --note is mandatory, and it is mandatory for a reason: the ledger's value is not
# the list of what happened. It is the reasoning that was current at the time. Six weeks
# later, "accepted" tells you nothing; "accepted — ran the suite myself, swung two knives
# it had not, both red" tells you exactly how much to trust it.
#
# Write the note as: what came back · how you checked it · what you measured.

set -euo pipefail

LEDGER="${LEDGER:-ledger.json}"

die() { printf 'accept: %s\n' "$1" >&2; exit 1; }

[ $# -ge 1 ] || die 'usage: accept.sh <station> --note "…" [--reopen "…"]'
STATION="$1"; shift

NOTE=""; REOPEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --note)   NOTE="${2:-}";   shift 2 ;;
    --reopen) REOPEN="${2:-}"; shift 2 ;;
    *)        die "unknown argument: $1" ;;
  esac
done

[ -f "$LEDGER" ] || die "no ledger at $LEDGER"
[ -n "$NOTE" ]   || die 'a --note is required. "accepted" on its own is not a record.'

python3 - "$LEDGER" "$STATION" "$NOTE" "$REOPEN" <<'PY'
import json, sys, datetime
ledger, station, note, reopen = sys.argv[1:5]
d = json.load(open(ledger))
agents = d.setdefault("agents", {})
prev = agents.get(station, {})
if prev.get("state") != "running":
    print(f"accept: warning — '{station}' was '{prev.get('state', 'unknown')}', not running.",
          file=sys.stderr)
task = prev.get("task", "")
agents[station] = {"state": "idle", "task": "", "since": ""}

stamp = f"{datetime.datetime.now():%Y-%m-%d %H:%M}"
entry = f"[accepted · {stamp}] {station} — {task}. {note}"
d.setdefault("backlog", []).insert(0, entry)
if reopen:
    d.setdefault("pending_decision", []).append(
        f"[open · {stamp}] from {station} / {task}: {reopen}")
json.dump(d, open(ledger, "w"), ensure_ascii=False, indent=2)
print(entry)
PY
