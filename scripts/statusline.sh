#!/usr/bin/env bash
# Reads the ledger and prints one line: who is running what, how many messages are
# waiting, how many items need a human decision. Hang it on your prompt or status bar
# so "who is busy" is always visible.
#
# Usage: statusline.sh [ledger path] [inbox path]

set -euo pipefail
LEDGER="${1:-ledger.json}"
INBOX="${2:-mailbox/to-hub}"

[ -f "$LEDGER" ] || { echo "no ledger"; exit 0; }

# Check the ledger against the machine, not only against itself. A station marked running
# whose process is gone is not a station running — it is a ledger nobody closed out. That is
# the same failure this whole model exists to catch, so the ledger does not get a pass either.
# kill -0 sends no signal; it only asks "could I signal this pid" — i.e. is it still alive.
busy=$(python3 - "$LEDGER" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
out = []
for name, a in d.get("agents", {}).items():
    if a.get("state") != "running":
        continue
    task, pid = a.get("task", "")[:18], a.get("pid")
    alive = None
    if isinstance(pid, int):
        try:
            os.kill(pid, 0)
            alive = True
        except ProcessLookupError:
            alive = False
        except PermissionError:
            alive = True          # exists, owned by another user
    out.append(f"!! {name}:ORPHANED(ledger says running, pid {pid} is gone)"
               if alive is False else f"{name}:{task}")
print(" | ".join(out) if out else "all idle")
PY
)

pending=$(python3 - "$LEDGER" <<'PY'
import json, sys
print(len(json.load(open(sys.argv[1])).get("pending_decision", [])))
PY
)

# find, not `ls | grep`: on an empty directory grep exits 1, and with pipefail that
# kills the whole script silently.
unread=$(find "$INBOX" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')

printf '%s  ·  inbox %s  ·  awaiting decision %s\n' "$busy" "$unread" "$pending"
