#!/usr/bin/env bash
#
# dispatch.sh — start one shift, and record it in the ledger. One action, not two.
#
#   ./scripts/dispatch.sh <station> <order-file> [--tools "<allowlist>"] [--fg]
#
# What it does
#   1. checks the station and the order exist, and that the station is idle
#   2. builds the launch prompt in a temp FILE, then passes it with "$(cat …)"
#   3. starts one agent process — background by default, log to disk
#   4. writes the ledger: this station is now running, on this order, since now
#
# Why the prompt goes through a file: a prompt written inline is interpreted by the
# shell first. Backticks in it become command substitution — the text you wrote gets
# executed, and the station receives an order with those lines silently removed. Both
# halves of that are bad. A file has neither problem.
#
# Why this script writes the ledger: because "dispatch and record are the same action"
# is a rule that gets broken the moment they are two commands. Here they cannot be.

set -euo pipefail

AGENT_CMD="${AGENT_CMD:-}"          # e.g. AGENT_CMD="claude -p"  — set for your agent CLI
STATIONS_DIR="${STATIONS_DIR:-.}"   # where station working directories live
MAILBOX="${MAILBOX:-mailbox}"
LEDGER="${LEDGER:-ledger.json}"
LOGS="${LOGS:-.shifts}"

die() { printf 'dispatch: %s\n' "$1" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: dispatch.sh <station> <order-file> [--tools \"…\"] [--fg]"
STATION="$1"; ORDER="$2"; shift 2

TOOLS=""; BACKGROUND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --tools) TOOLS="${2:-}"; shift 2 ;;
    --fg)    BACKGROUND=0; shift ;;
    *)       die "unknown argument: $1" ;;
  esac
done

[ -n "$AGENT_CMD" ]     || die "set AGENT_CMD to your agent CLI, e.g. AGENT_CMD=\"claude -p\""
[ -f "$ORDER" ]         || die "no such order: $ORDER"
[ -d "$STATIONS_DIR/$STATION" ] || die "no working directory for station: $STATION"
[ -f "$LEDGER" ]        || die "no ledger at $LEDGER"

# --- refuse to dispatch on top of a running shift -----------------------------
state=$(python3 - "$LEDGER" "$STATION" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("agents", {}).get(sys.argv[2], {}).get("state", "unknown"))
PY
)
[ "$state" = "idle" ] || die "station '$STATION' is '$state', not idle. One shift at a time per station."

# --- build the prompt in a file ----------------------------------------------
mkdir -p "$LOGS"
stamp=$(date +%Y%m%d-%H%M%S)
slug=$(basename "$ORDER" .md)
prompt_file="$LOGS/$stamp-$STATION-$slug.prompt.txt"
log_file="$LOGS/$stamp-$STATION-$slug.log"

needs=$(sed -n 's/^needs:[[:space:]]*//p' "$ORDER" | head -1)
reply=$(sed -n 's/^reply:[[:space:]]*//p' "$ORDER" | head -1)

{
  echo "You are the $STATION station. Read the order at $(cd "$(dirname "$ORDER")" && pwd)/$(basename "$ORDER") and follow it strictly."
  echo
  [ -n "$needs" ] && echo "This shift is authorised to execute. What is being asked: $needs"
  echo
  echo "Non-negotiable, regardless of what the order says:"
  echo "- Work only inside your own territory. Do not touch another station's."
  echo "- Do not merge, deploy, publish, or force push. A human presses those."
  echo "- Acceptance takes artifacts. Attach the diff, the check output, the exact"
  echo "  failure message of every mutation check — not a summary of them."
  echo "- Anything you could not verify: say what you tried and why it failed."
  echo "  Never present reasoning as measurement."
  echo "- End your reply with a section called 'found but not done'."
  echo
  [ -n "$reply" ] && echo "Write your reply to $MAILBOX/$reply with status: NEW."
} > "$prompt_file"

# --- launch one shift ---------------------------------------------------------
launch() {
  ( cd "$STATIONS_DIR/$STATION" && \
    if [ -n "$TOOLS" ]; then
      $AGENT_CMD "$(cat "$OLDPWD/$prompt_file")" --allowedTools "$TOOLS"
    else
      $AGENT_CMD "$(cat "$OLDPWD/$prompt_file")"
    fi ) >"$log_file" 2>&1
}

if [ "$BACKGROUND" -eq 1 ]; then
  launch &
  pid=$!
else
  launch
  pid=$$
fi

# --- record, in the same action ----------------------------------------------
python3 - "$LEDGER" "$STATION" "$ORDER" "$log_file" <<'PY'
import json, sys, datetime
ledger, station, order, log = sys.argv[1:5]
d = json.load(open(ledger))
d.setdefault("agents", {})[station] = {
    "state": "running",
    "task":  order,
    "since": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "log":   log,
}
d.setdefault("backlog", []).insert(0,
    f"[dispatched · {datetime.datetime.now():%Y-%m-%d %H:%M}] {station} ← {order}. Log: {log}.")
json.dump(d, open(ledger, "w"), ensure_ascii=False, indent=2)
PY

printf 'dispatched  station=%s  order=%s  pid=%s\n' "$STATION" "$ORDER" "$pid"
printf 'log         %s\n' "$log_file"
printf 'reply due   %s\n' "${reply:-<not declared in the order>}"
printf '\nWhen it lands: read the artifacts, not the reply. Then ./scripts/accept.sh %s --note "…"\n' "$STATION"
