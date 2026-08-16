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

busy=$(python3 - "$LEDGER" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
out = []
for name, a in d.get("agents", {}).items():
    if a.get("state") == "running":
        out.append(f"{name}:{a.get('task','')[:18]}")
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
