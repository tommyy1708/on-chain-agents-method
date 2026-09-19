#!/usr/bin/env bash
#
# check-transcription.test.sh — tests for scripts/check-transcription.sh and for the
# --from-review gate in scripts/dispatch.sh.
#
#   ./tests/check-transcription.test.sh
#
# Self-contained: every fixture lives in a mktemp -d directory that is removed on exit.
# The dispatch cases run against a COPY of ledger.example.json, never the real ledger.
# One PASS/FAIL line per case, a summary last, non-zero exit if anything failed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-transcription.sh"
DISPATCH="$ROOT/scripts/dispatch.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=$((fail + 1)); }

# run_check <review> <order>: sets $rc, $out, $err
run_check() {
  rc=0
  "$CHECK" "$1" "$2" >"$T/out" 2>"$T/err" || rc=$?
  out="$(cat "$T/out")"; err="$(cat "$T/err")"
}

# expect <name> <exit code> [<text stderr must contain>]
expect() {
  local name="$1" want="$2" needle="${3:-}"
  if [ "$rc" -ne "$want" ]; then
    bad "$name" "exit $rc, wanted $want · stderr: $err"
  elif [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$err"; then
    bad "$name" "stderr lacks '$needle' · stderr: $err"
  else
    ok "$name"
  fi
}

# --- fixtures ----------------------------------------------------------------
cat >"$T/review3.md" <<'EOF'
---
status: NEW
from: review
---

# 审查结论

## Blocker

### B1 · 空输入时崩溃
位置、复现步骤。

### B2 · 日志泄露令牌
位置、复现步骤。

### B3 · 重试没有上限
位置、复现步骤。

## Should-fix
- 命名不一致
EOF

order() {  # order <file> <transcription lines…>
  local f="$1"; shift
  {
    printf -- '---\nstatus: NEW\nfrom: hub\n---\n\n# 返工\n\n## 审查结论的转写\n\n来源:review.md\n\n'
    printf '%s\n' "$@"
    printf '\n## 怎么做\n\n1. 先写测试\n'
  } >"$f"
}

# --- T1 complete --------------------------------------------------------------
order "$T/o1.md" "- B1 → 修:空输入返回错误" "- B2 → 修:日志脱敏" "- B3 → 不修:上游已限流;人决定的"
run_check "$T/review3.md" "$T/o1.md"
expect "T1 complete" 0
grep -qF 'check-transcription: ok · 3 blockers · 2 fix · 1 not fixing' <<<"$out" \
  && ok "T1 summary line" || bad "T1 summary line" "stdout: $out"

# --- T2 missing B2 ------------------------------------------------------------
order "$T/o2.md" "- B1 → 修:空输入返回错误" "- B3 → 不修:上游已限流"
run_check "$T/review3.md" "$T/o2.md"
expect "T2 missing B2" 1 "check-transcription: missing B2"

# --- T3 not fixing, empty reason ----------------------------------------------
order "$T/o3.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → 不修:"
run_check "$T/review3.md" "$T/o3.md"
expect "T3 not fixing, empty reason" 1 "B3: not fixing without a reason"

# whitespace only is empty too — the English template leaves a space after the colon
order "$T/o3b.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → not fixing:   "
run_check "$T/review3.md" "$T/o3b.md"
expect "T3b not fixing, whitespace-only reason" 1 "B3: not fixing without a reason"

# --- T4 extra B9 --------------------------------------------------------------
order "$T/o4.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → 修:z" "- B9 → 修:凭空多出来"
run_check "$T/review3.md" "$T/o4.md"
expect "T4 unknown B9" 1 "unknown B9 (not in the review reply)"

# --- T5 duplicate -------------------------------------------------------------
order "$T/o5.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → 修:z" "- B1 → 不修:改主意了"
run_check "$T/review3.md" "$T/o5.md"
expect "T5 B1 twice" 1 "B1 appears twice"

# --- T6 no blockers -----------------------------------------------------------
printf -- '# 审查结论\n\n## Blocker\n\n无 blocker\n\n## Should-fix\n- 命名\n' >"$T/review0.md"
printf -- '# 工单\n\n## 要什么\n\n改名。\n' >"$T/o6.md"
run_check "$T/review0.md" "$T/o6.md"
expect "T6 no blockers" 0

# --- T7 both languages, both colons -------------------------------------------
cat >"$T/review4.md" <<'EOF'
### B1 · one
### B2 · two
### B3 · three
### B4 · four
EOF
order "$T/o7.md" "- B1 → 修:半角" "- B2 → fix: english" "- B3 → 不修:全角冒号的理由" "- B4 → not fixing:english, full-width colon"
run_check "$T/review4.md" "$T/o7.md"
expect "T7 zh/en, half/full-width colons" 0
grep -qF 'ok · 4 blockers · 2 fix · 2 not fixing' <<<"$out" \
  && ok "T7 counts" || bad "T7 counts" "stdout: $out"

# --- T10 code block in the review is not counted ------------------------------
cat >"$T/review-fence.md" <<'EOF'
# 审查结论

格式示例:

```markdown
### B1 · 示例
### B7 · 也只是示例
```

### B1 · 真的问题一
### B2 · 真的问题二
EOF
order "$T/o10.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-fence.md" "$T/o10.md"
expect "T10 review code block ignored" 0

# and a code block in the order is not counted either
order "$T/o10b.md" "- B1 → 修:x" "- B2 → 修:y" '```' "- B1 → 修:示例,不算重复" "- B9 → 修:示例,不算多出" '```'
run_check "$T/review-fence.md" "$T/o10b.md"
expect "T10b order code block ignored" 0

# --- T11 placeholder not filled -----------------------------------------------
order "$T/o11.md" "- B1 → 修:<转写后的要求>" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o11.md"
expect "T11 placeholder (zh)" 1 "B1: placeholder not filled"

order "$T/o11b.md" "- B1 → fix: <the requirement, as transcribed>" "- B2 → 修:y" "- B3 → not fixing: <reason; who decided>"
run_check "$T/review3.md" "$T/o11b.md"
expect "T11b placeholder (en, space after colon)" 1 "B3: placeholder not filled"

# angle brackets inside real content are fine
order "$T/o12.md" "- B1 → 修:返回值改成 Vec<T>" "- B2 → 修:<b>加粗</b> 去掉" "- B3 → 不修:见 <#42>、<#43>"
run_check "$T/review3.md" "$T/o12.md"
expect "T12 angle brackets in real content" 0

# --- usage / missing file -----------------------------------------------------
run_check "$T/review3.md" "$T/nope.md"
expect "T13 missing file → 2" 2
rc=0; "$CHECK" "$T/review3.md" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && ok "T13b wrong arg count → 2" || bad "T13b wrong arg count → 2" "exit $rc"

# --- review side fails closed (D1 rework 1) -----------------------------------
# T6 above already covers "review says 无 blocker, order has no transcription → 0".
printf -- '# 审查结论\n\n## Blocker\n\nNo blockers.\n' >"$T/review0en.md"
run_check "$T/review0en.md" "$T/o6.md"
expect "T6b 'No blockers' (any case) → 0" 0

printf '%s\n' '# 审查结论' '' '### B1 · 空输入崩溃' 'x' '### B2 · 令牌泄露' 'x' '### B3·重试无上限' 'x' >"$T/review-dot.md"
order "$T/o15.md" "- B1 → 修:空输入返回错误" "- B2 → 修:日志脱敏"
run_check "$T/review-dot.md" "$T/o15.md"
expect "T15 '### B3·' heading, order has B1 B2" 1 "malformed blocker heading at line 7: ### B3·重试无上限"

order "$T/o16.md" "- B1 → 修:空输入返回错误" "- B2 → 修:日志脱敏" "- B3 → 修:加上限"
run_check "$T/review-dot.md" "$T/o16.md"
expect "T16 same, order has B1 B2 B3 — still malformed" 1 "malformed blocker heading"

printf '%s\n' '### B1 — 空输入崩溃' '### B2 — 令牌泄露' '### B3 — 重试无上限' >"$T/review-dash.md"
order "$T/o17.md"
run_check "$T/review-dash.md" "$T/o17.md"
expect "T17 all headings '### Bn —', empty order" 1 "malformed blocker heading"
expect "T17b … and no strict heading, no 无 blocker" 1 'review reply numbers no blockers and does not say "无 blocker" / "no blockers"'

printf -- '# 审查结论\n\n## Blocker\n\n都挺好。\n' >"$T/review-silent.md"
run_check "$T/review-silent.md" "$T/o6.md"
expect "T18 no ### B and no 无 blocker" 1 "review reply numbers no blockers"

cat >"$T/review-prose.md" <<'EOF'
### B1 · 空输入崩溃
B1 和 B2 的共同根因是没有校验输入。
### B2 · 令牌泄露
EOF
order "$T/o19.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-prose.md" "$T/o19.md"
expect "T19 prose line starting 'B1 和 B2' is not a heading" 0

printf '%s\n' '### B1 · 空输入崩溃' 'x' '### B2 · 令牌泄露' 'x' '### B2 · 重试无上限' 'x' >"$T/review-dup.md"
order "$T/o20.md" "- B1 → 修:空输入返回错误" "- B2 → 修:日志脱敏"
run_check "$T/review-dup.md" "$T/o20.md"
expect "T20 review raises B2 twice" 1 "B2 raised twice in the review reply"

printf '%s\n' '### B1 · one' '### B3 · three' >"$T/review-gap.md"
order "$T/o21.md" "- B1 → 修:x" "- B3 → 修:z"
run_check "$T/review-gap.md" "$T/o21.md"
expect "T21 review has B1 B3 only" 1 "review reply skips B2 (numbering must run B1, B2, … without gaps)"

printf '%s\n' '### B1 · 空输入崩溃' '```` ``` ```` 开头的行是行内代码' '### B2 · 令牌泄露' 'x' >"$T/review-inline.md"
order "$T/o22.md" "- B1 → 修:空输入返回错误"
run_check "$T/review-inline.md" "$T/o22.md"
expect "T22 line opening with inline code is not a fence" 1 "missing B2"

printf '%s\n' '### B1 · one' '```' '### B2 · two' >"$T/review-open.md"
order "$T/o23.md" "- B1 → 修:x"
run_check "$T/review-open.md" "$T/o23.md"
expect "T23 unclosed fence in the review" 1 "unclosed code fence opened at line 2"

order "$T/o23b.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → 修:z" '~~~'
run_check "$T/review3.md" "$T/o23b.md"
expect "T23b unclosed fence in the order" 1 "unclosed code fence opened at line"

printf '%s\n' '### B1 · one' '~~~' '### B9 · x' '~~~' >"$T/review-tilde.md"
order "$T/o24.md" "- B1 → 修:x"
run_check "$T/review-tilde.md" "$T/o24.md"
expect "T24 ~~~ fence: B9 inside is not counted" 0

printf '%s\n' '### B1 · one' '````markdown' '```' '### B7 · 示例' '````' '### B2 · two' >"$T/review-4tick.md"
order "$T/o25.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-4tick.md" "$T/o25.md"
expect "T25 \`\`\` inside a \`\`\`\` fence: B7 not counted, B2 counted" 0

order "$T/o26.md" "- B1 → 修:" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o26.md"
expect "T26 empty fix" 1 "B1: empty entry"

order "$T/o27.md" "- B1 → 修:…" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o27.md"
expect "T27 fix is just …" 1 "B1: placeholder not filled"

order "$T/o27b.md" "- B1 → 修:x" "- B2 → fix: ..." "- B3 → 修:z"
run_check "$T/review3.md" "$T/o27b.md"
expect "T27b fix is just ..." 1 "B2: placeholder not filled"

order "$T/o28.md" "- B1 → 修：空输入返回错误" "- B2 → 不修：上游已脱敏" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o28.md"
expect "T28 full-width colon" 0

: >"$T/review11.md"
for i in 1 2 3 4 5 6 7 8 9 10 11; do printf '### B%d · item %d\n' "$i" "$i" >>"$T/review11.md"; done
order "$T/o29.md" "- B1 → 修:a" "- B2 → 修:b" "- B3 → 修:c" "- B4 → 修:d" "- B5 → 修:e" \
  "- B6 → 修:f" "- B7 → 修:g" "- B8 → 修:h" "- B9 → 修:i" "- B11 → 修:k"
run_check "$T/review11.md" "$T/o29.md"
expect "T29 B1–B11, order misses B10" 1 "missing B10"

# the real review that started this rework, against the real transcription of it
run_check "$ROOT/tests/fixtures/review-2026-09-19-d1.md" "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-1.md"
expect "T30 real regression: d1 review vs rework-1 transcription" 0
grep -qF 'ok · 3 blockers · 3 fix · 0 not fixing' <<<"$out" \
  && ok "T30 counts" || bad "T30 counts" "stdout: $out"

# --- dispatch gate ------------------------------------------------------------
# station-b is idle in ledger.example.json
setup_dispatch() {
  rm -rf "$T/d"; mkdir -p "$T/d/stations/station-b"
  cp "$ROOT/ledger.example.json" "$T/d/ledger.json"
  cp "$T/d/ledger.json" "$T/d/ledger.before"
}
run_dispatch() {  # run_dispatch <order>
  rc=0
  ( cd "$T/d" && AGENT_CMD=echo STATIONS_DIR="$T/d/stations" LEDGER="$T/d/ledger.json" \
      LOGS="$T/d/logs" "$DISPATCH" station-b "$1" --fg --from-review "$T/review3.md" ) \
    >"$T/out" 2>"$T/err" || rc=$?
  out="$(cat "$T/out")"; err="$(cat "$T/err")"
}
logs_empty() { [ ! -d "$T/d/logs" ] || [ -z "$(ls -A "$T/d/logs")" ]; }
station_state() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["agents"]["station-b"]["state"])' "$T/d/ledger.json"
}

# T8 refuse
setup_dispatch
run_dispatch "$T/o2.md"
if [ "$rc" -eq 0 ]; then bad "T8 dispatch refuses" "exit 0 · $out"
elif ! cmp -s "$T/d/ledger.before" "$T/d/ledger.json"; then bad "T8 dispatch refuses" "ledger changed"
elif ! logs_empty; then bad "T8 dispatch refuses" "files in LOGS: $(ls -A "$T/d/logs")"
elif ! grep -qF "missing B2" <<<"$err"; then bad "T8 dispatch refuses" "check output not passed through · stderr: $err"
else ok "T8 dispatch refuses (exit $rc, ledger byte-identical, no logs)"; fi

# T9 allow
setup_dispatch
run_dispatch "$T/o1.md"
if [ "$rc" -ne 0 ]; then bad "T9 dispatch allows" "exit $rc · $err"
elif [ "$(station_state)" != "running" ]; then bad "T9 dispatch allows" "state is $(station_state)"
else ok "T9 dispatch allows (station-b running)"; fi

# without --from-review, a rework order that would fail the check still dispatches
setup_dispatch
rc=0
( cd "$T/d" && AGENT_CMD=echo STATIONS_DIR="$T/d/stations" LEDGER="$T/d/ledger.json" \
    LOGS="$T/d/logs" "$DISPATCH" station-b "$T/o2.md" --fg ) >"$T/out" 2>"$T/err" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(station_state)" = "running" ]; then ok "T14 no --from-review: unchanged, no gate"
else bad "T14 no --from-review: unchanged, no gate" "exit $rc · $(cat "$T/err")"; fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
