#!/usr/bin/env bash
#
# dispatch.sh — start one shift, and record it in the ledger. One action, not two.
#
#   ./scripts/dispatch.sh <station> <order-file> [--tools "<list>"] [--allow "<list>"] [--fg]
#
# What it does
#   1. checks the station and the order exist, and that the station is idle
#      — and reads the order's front matter "review:" line: "review: none", or the
#      review reply's path relative to $MAILBOX (like "reply:"). An order without one is
#      not dispatched. With a path, the order must account for every blocker in that
#      review (scripts/check-transcription.sh).
#      On a failure nothing is written: no prompt, no log, no shift, no ledger entry.
#   2. builds the launch prompt in a temp FILE, then passes it with "$(cat …)"
#   3. starts one agent process — background by default, log to disk
#   4. writes the ledger: this station is now running, on this order, since now,
#      AND the process id, so the status display can check the ledger against reality.
#      With --fg the ledger is written first and the pid dropped when the shift returns,
#      so the recorded pid is alive for exactly as long as the shift is — see below.
#
# Two different permission flags, and they are not interchangeable
#   --tools "…"  the set of tools that EXIST for this shift. This is the boundary.
#   --allow "…"  tools that are pre-approved, so the shift is not stopped to ask.
#                Pre-approval is not restriction: measured on Claude Code 2.1.247, a shift
#                launched with --allowedTools "Read" still ran shell commands. Only --tools
#                removed the tool. Test your own CLI once; do not assume.
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

[ $# -ge 2 ] || die "usage: dispatch.sh <station> <order-file> [--tools \"…\"] [--allow \"…\"] [--fg]"
STATION="$1"; ORDER="$2"; shift 2

TOOLS=""; ALLOW=""; BACKGROUND=1
while [ $# -gt 0 ]; do
  case "$1" in
    --tools) TOOLS="${2:-}"; shift 2 ;;
    --allow) ALLOW="${2:-}"; shift 2 ;;
    --fg)    BACKGROUND=0; shift ;;
    --from-review) die "--from-review was removed: declare the review in the order's front matter (review: <path relative to mailbox/>)" ;;
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

# --- a rework order must account for every blocker ----------------------------
# Checked here, before anything is written, for the same reason the ledger is written
# by this script: a check that is a separate command is a check that gets skipped.
# Every order declares "review:" in its front matter, so whether the check runs never
# depends on recognising a line in the body, or on a flag someone has to remember.
CHECK="$(dirname "${BASH_SOURCE[0]}")/check-transcription.sh"
review=$("$CHECK" --review-path "$ORDER") || die "cannot read the review: line in $ORDER. Nothing dispatched."
if [ "$review" != "none" ]; then
  [ -f "$MAILBOX/$review" ] || die "review named in the order does not exist: $MAILBOX/$review. Nothing dispatched."
  "$CHECK" "$MAILBOX/$review" "$ORDER" \
    || die "rework order does not pass check-transcription against $MAILBOX/$review. Nothing dispatched."
fi

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
  echo
  echo "Sign off, always, as the very last thing you do — after the reply is on disk:"
  echo "  print one line, exactly this shape, and nothing after it:"
  echo "  SHIFT-END $STATION $slug <done|failed|stuck> · <one sentence> · reply ${reply:-<none>}"
  echo "Emit it even if you are stopping early — use 'stuck' and say where you stopped."
  echo "Dying quietly is the worst outcome: it looks identical to still working."
  echo "If your tooling can message the dispatching session directly, send that same line"
  echo "there as well. The reply file remains the record; this line is only a doorbell."
} > "$prompt_file"

# --- launch one shift ---------------------------------------------------------
launch() {
  ( cd "$STATIONS_DIR/$STATION" && \
    set -- "$(cat "$OLDPWD/$prompt_file")"
    [ -n "$TOOLS" ] && set -- "$@" --tools "$TOOLS"
    [ -n "$ALLOW" ] && set -- "$@" --allowedTools "$ALLOW"
    $AGENT_CMD "$@" ) >"$log_file" 2>&1
}

# --- record, in the same action ----------------------------------------------
record() {  # record <pid>: this station is now running this order, under this process
  python3 - "$LEDGER" "$STATION" "$ORDER" "$log_file" "$1" <<'PY'
import json, sys, datetime
ledger, station, order, log, pid = sys.argv[1:6]
d = json.load(open(ledger))
d.setdefault("agents", {})[station] = {
    "state": "running",
    "task":  order,
    "since": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
    "log":   log,
    # The witness. Discipline says the hub will always close this out; the pid is what
    # catches the night it doesn't. statusline.sh checks it with kill -0.
    "pid":   int(pid),
}
d.setdefault("backlog", []).insert(0,
    f"[dispatched · {datetime.datetime.now():%Y-%m-%d %H:%M}] {station} ← {order}. Log: {log}.")
json.dump(d, open(ledger, "w"), ensure_ascii=False, indent=2)
PY
}

forget_pid() {  # the shift has returned; the pid it ran under is on its way out
  python3 - "$LEDGER" "$STATION" <<'PY'
import json, sys
ledger, station = sys.argv[1:3]
d = json.load(open(ledger))
d.get("agents", {}).get(station, {}).pop("pid", None)
json.dump(d, open(ledger, "w"), ensure_ascii=False, indent=2)
PY
}

if [ "$BACKGROUND" -eq 1 ]; then
  launch &
  pid=$!
  record "$pid"
else
  # Foreground: record BEFORE the shift, not after, and drop the pid after.
  #
  # Recorded after, the only process left to name is this script ($$), and it is exiting
  # as the entry is written — so statusline.sh reads a "running" station whose pid is gone
  # and reports ORPHANED for a shift that ran to the end. That is the status display
  # announcing a crash that never happened, which is the failure this whole model exists
  # to catch, pointing the other way. Recorded first, the pid is this script, and it is
  # alive for exactly as long as the shift is. It also closes the window where a
  # foreground shift is running and the ledger still says the station is idle.
  #
  # The entry keeps saying "running" once the shift returns, because it is still open:
  # accept.sh is what closes it out. Only the pid goes, since there is no longer a process
  # for the status display to check. Background mode is unchanged — there the pid is a
  # real child, and ORPHANED after it dies is the reminder nobody was watching.
  pid=$$
  record "$pid"
  shift_rc=0
  launch || shift_rc=$?
  forget_pid
  if [ "$shift_rc" -ne 0 ]; then
    printf 'dispatch: the shift exited %s. Log: %s\n' "$shift_rc" "$log_file" >&2
    printf 'dispatch: the ledger entry stands — close it out with accept.sh.\n' >&2
    exit "$shift_rc"
  fi
fi

printf 'dispatched  station=%s  order=%s  pid=%s\n' "$STATION" "$ORDER" "$pid"
printf 'log         %s\n' "$log_file"
printf 'reply due   %s\n' "${reply:-<not declared in the order>}"
printf '\nWhen it lands: read the artifacts, not the reply. Then ./scripts/accept.sh %s --note "…"\n' "$STATION"
