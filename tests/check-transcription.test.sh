#!/usr/bin/env bash
#
# check-transcription.test.sh — tests for scripts/check-transcription.sh and for the
# review-source gate in scripts/dispatch.sh.
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
  "$CHECK" "$@" >"$T/out" 2>"$T/err" || rc=$?
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
review() {  # review <file> <blockers: value> <body lines…>
  local f="$1" manifest="$2"; shift 2
  {
    printf -- '---\nstatus: NEW\nfrom: review\nblockers: %s\n---\n\n# 审查结论\n\n' "$manifest"
    printf '%s\n' "$@"
  } >"$f"
}

cat >"$T/review3.md" <<'EOF'
---
status: NEW
from: review
blockers: B1, B2, B3
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
review "$T/review0.md" "none" '## Blocker' '' '无。' '' '## Should-fix' '- 命名'
printf -- '# 工单\n\n## 要什么\n\n改名。\n' >"$T/o6.md"
run_check "$T/review0.md" "$T/o6.md"
expect "T6 blockers: none, no headings, order without transcription" 0

review "$T/review0en.md" "NONE" '## Blocker' '' 'Nothing blocks.'
run_check "$T/review0en.md" "$T/o6.md"
expect "T6b blockers: NONE (any case) → 0" 0

review "$T/review0h.md" "none" '### B1 · 其实有一条'
run_check "$T/review0h.md" "$T/o6.md"
expect "T6c blockers: none + one strict heading" 1 'B1 has a "### B1 · " heading but is not in blockers:'

# --- T7 both languages, both colons -------------------------------------------
review "$T/review4.md" "B1, B2, B3, B4" '### B1 · one' '### B2 · two' '### B3 · three' '### B4 · four'
order "$T/o7.md" "- B1 → 修:半角" "- B2 → fix: english" "- B3 → 不修：全角冒号的理由" "- B4 → not fixing：english, full-width colon"
run_check "$T/review4.md" "$T/o7.md"
expect "T7 zh/en, half/full-width colons" 0
grep -qF 'ok · 4 blockers · 2 fix · 2 not fixing' <<<"$out" \
  && ok "T7 counts" || bad "T7 counts" "stdout: $out"

# --- T10 code block in the review is not counted ------------------------------
review "$T/review-fence.md" "B1, B2" '格式示例:' '' '```markdown' '### B1 · 示例' '### B7 · 也只是示例' '```' '' \
  '### B1 · 真的问题一' '### B2 · 真的问题二'
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

# --- the blockers: manifest (D1 rework 2) -------------------------------------
printf -- '# 审查结论\n\n### B1 · 空输入崩溃\n' >"$T/review-nofm.md"
order "$T/o31.md" "- B1 → 修:x"
run_check "$T/review-nofm.md" "$T/o31.md"
expect "T31 no front matter" 1 'review reply has no "blockers:" line in its front matter'

review "$T/review-digits.md" "1, 2"
order "$T/o32.md"
run_check "$T/review-digits.md" "$T/o32.md"
expect "T32 blockers: 1, 2" 1 "review reply blockers line unreadable: blockers: 1, 2"

printf '%s\n' '---' 'status: NEW' 'from: review' '---' '' '# 审查结论' '' 'blockers: B1' '' '### B1 · 空输入崩溃' >"$T/review-body.md"
run_check "$T/review-body.md" "$T/o31.md"
expect "T33 blockers: line in the body, not the front matter" 1 'review reply has no "blockers:" line in its front matter'

# the seven headings from the rework-1 review, B3 each time; the order accounts for B1 B2
order "$T/o34.md" "- B1 → 修:空输入返回错误" "- B2 → 修:日志脱敏"
i=0
for h in '### ⛔ B3 · 重试没有上限' '### Blocker 3 · 重试没有上限' '### b3 · 重试没有上限' '### [B3] 重试没有上限' \
         '### B３ · 重试没有上限' '### `B3` · 重试没有上限' '### 3. B3 · 重试没有上限'; do
  i=$((i + 1))
  review "$T/review-h$i.md" "B1, B2, B3" '### B1 · 空输入崩溃' 'x' '### B2 · 令牌泄露' 'x' "$h" 'x'
  run_check "$T/review-h$i.md" "$T/o34.md"
  expect "T34.$i listed B3, heading '$h'" 1 'B3 is in blockers: but has no "### B3 · " heading'
done

review "$T/review-b4.md" "B1, B2, B3" '### B1 · a' '### B2 · b' '### B3 · c' '### B4 · 清单里没有'
run_check "$T/review-b4.md" "$T/o1.md"
expect "T35 extra '### B4 · ' heading" 1 'B4 has a "### B4 · " heading but is not in blockers:'

review "$T/review-13.md" "B1, B3" '### B1 · a' '### B3 · c'
order "$T/o36.md" "- B1 → 修:x" "- B3 → 修:z"
run_check "$T/review-13.md" "$T/o36.md"
expect "T36 blockers: B1, B3" 1 "blockers: skips B2"

review "$T/review-23.md" "B2, B3" '### B2 · b' '### B3 · c'
order "$T/o37.md" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review-23.md" "$T/o37.md"
expect "T37 blockers: B2, B3" 1 "blockers: skips B1"

review "$T/review-dupm.md" "B1, B2, B2" '### B1 · a' '### B2 · b'
order "$T/o38.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-dupm.md" "$T/o38.md"
expect "T38 B2 listed twice" 1 "B2 listed twice in blockers:"

# a re-review talks about the previous round's numbers — none of it is a heading
review "$T/review-prev.md" "B1" '上一轮的 B1–B3 都已修复。' '**B1**:已修,复现改为拦下。' '#### B2(上轮)已修' \
  '### B1 · 新问题' '#### B1 复现' 'B1 和 B2 的共同根因是没有校验输入。'
order "$T/o39.md" "- B1 → 修:x"
run_check "$T/review-prev.md" "$T/o39.md"
expect "T39 previous round's numbers in prose, bold, #### — no effect" 0

review "$T/review-dup.md" "B1, B2" '### B1 · 空输入崩溃' 'x' '### B2 · 令牌泄露' 'x' '### B2 · 重试无上限' 'x'
order "$T/o20.md" "- B1 → 修:空输入返回错误" "- B2 → 修:日志脱敏"
run_check "$T/review-dup.md" "$T/o20.md"
expect "T20 review raises B2 twice" 1 "B2 raised twice in the review reply"

printf -- '---\nblockers: B1 B2 B3 B4 B5 B6 B7 B8 B9 B10 B11\n---\n' >"$T/review11.md"
for i in 1 2 3 4 5 6 7 8 9 10 11; do printf '### B%d · item %d\n' "$i" "$i" >>"$T/review11.md"; done
order "$T/o29.md" "- B1 → 修:a" "- B2 → 修:b" "- B3 → 修:c" "- B4 → 修:d" "- B5 → 修:e" \
  "- B6 → 修:f" "- B7 → 修:g" "- B8 → 修:h" "- B9 → 修:i" "- B11 → 修:k"
run_check "$T/review11.md" "$T/o29.md"
expect "T29 B1–B11 (space-separated list), order misses B10" 1 "missing B10"

# --- rework order entries -----------------------------------------------------
order "$T/o26.md" "- B1 → 修:" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o26.md"
expect "T26 empty fix" 1 "B1: empty entry"

order "$T/o27.md" "- B1 → 修:…" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o27.md"
expect "T27 fix is just …" 1 "B1: placeholder not filled"

order "$T/o27b.md" "- B1 → 修:x" "- B2 → fix: ..." "- B3 → 修:z"
run_check "$T/review3.md" "$T/o27b.md"
expect "T27b fix is just ..." 1 "B2: placeholder not filled"

order "$T/o40.md" "- B1 → 修:……" "- B2 → 修:TBD" "- B3 → 不修:待补"
run_check "$T/review3.md" "$T/o40.md"
expect "T40 修:……" 1 "B1: placeholder not filled"
expect "T40b 修:TBD" 1 "B2: placeholder not filled"
expect "T40c 不修:待补" 1 "B3: placeholder not filled"

order "$T/o41.md" "- B1 → fix: todo" "- B2 → 修:待定" "- B3 → 修:。。。不是占位,是内容"
run_check "$T/review3.md" "$T/o41.md"
expect "T41 fix: todo" 1 "B1: placeholder not filled"
expect "T41b 修:待定" 1 "B2: placeholder not filled"
grep -qF "B3:" <<<"$err" && bad "T41c text after dots is real content" "stderr: $err" || ok "T41c text after dots is real content"

order "$T/o28.md" "- B1 → 修：空输入返回错误" "- B2 → 不修：上游已脱敏" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o28.md"
expect "T28 full-width colon" 0

# --- code fences (CommonMark) -------------------------------------------------
review "$T/review-inline.md" "B1, B2" '### B1 · 空输入崩溃' '```` ``` ```` 开头的行是行内代码' '### B2 · 令牌泄露' 'x'
order "$T/o22.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-inline.md" "$T/o22.md"
expect "T22 line opening with inline code is not a fence" 0

review "$T/review-tilde.md" "B1" '### B1 · one' '~~~' '### B9 · x' '~~~'
order "$T/o24.md" "- B1 → 修:x"
run_check "$T/review-tilde.md" "$T/o24.md"
expect "T24 ~~~ fence: B9 inside is not counted" 0

review "$T/review-4tick.md" "B1, B2" '### B1 · one' '````markdown' '```' '### B7 · 示例' '````' '### B2 · two'
order "$T/o25.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-4tick.md" "$T/o25.md"
expect "T25 \`\`\` inside a \`\`\`\` fence: B7 not counted, B2 counted" 0

review "$T/review-f1.md" "B1" '### B1 · one' '~~~' '```' '### B9 · 示例' '```' '~~~'
run_check "$T/review-f1.md" "$T/o24.md"
expect "T42 \`\`\` does not close a ~~~ fence" 0

review "$T/review-f2.md" "B1" '### B1 · one' '```' '```python' '### B9 · 示例' '```'
run_check "$T/review-f2.md" "$T/o24.md"
expect "T43 a closing fence cannot carry an info string" 0

review "$T/review-f3.md" "B1, B2" '### B1 · one' '    ~~~' '### B2 · two' '    ~~~'
order "$T/o44.md" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review-f3.md" "$T/o44.md"
expect "T44 indented 4 spaces is not a fence" 0

review "$T/review-f4.md" "B1" '### B1 · one' '~~~ a`b' '### B9 · 示例' '~~~'
run_check "$T/review-f4.md" "$T/o24.md"
expect "T45 ~~~ info string may hold a backtick" 0

review "$T/review-open.md" "B1" '### B1 · one' '```' '### B2 · two'
order "$T/o23.md" "- B1 → 修:x"
run_check "$T/review-open.md" "$T/o23.md"
expect "T23 unclosed fence in the review" 1 "unclosed code fence in review reply, opened at line 10"

order "$T/o23b.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → 修:z" '~~~'
run_check "$T/review3.md" "$T/o23b.md"
expect "T23b unclosed fence in the order" 1 "unclosed code fence in rework order, opened at line"

# --- real regression ----------------------------------------------------------
# The real review that started D1, against the real transcription of it. Old format: no
# manifest. It is no longer accepted, and this pins that.
run_check "$ROOT/tests/fixtures/review-2026-09-19-d1.md" "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-1.md"
expect "T30 real regression, old format (no blockers: line)" 1 'review reply has no "blockers:" line in its front matter'

# the same reply with one line added to its front matter
awk 'NR == 2 { print "blockers: B1, B2, B3" } { print }' "$ROOT/tests/fixtures/review-2026-09-19-d1.md" >"$T/review-d1.md"
run_check "$T/review-d1.md" "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-1.md"
expect "T30b real regression + 'blockers: B1, B2, B3'" 0
grep -qF 'ok · 3 blockers · 3 fix · 0 not fixing' <<<"$out" \
  && ok "T30b counts" || bad "T30b counts" "stdout: $out"

# --- --source -----------------------------------------------------------------
run_check --source "$T/o1.md"
[ "$rc" -eq 0 ] && [ "$out" = "review.md" ] && ok "T46 --source: 来源 outside a fence → path" \
  || bad "T46 --source: 来源 outside a fence → path" "exit $rc · stdout '$out' · stderr $err"

printf '%s\n' '# 工单' '' 'Source: /tmp/some review.md' >"$T/o46b.md"
run_check --source "$T/o46b.md"
[ "$rc" -eq 0 ] && [ "$out" = "/tmp/some review.md" ] && ok "T46b --source: 'Source:' → path, as written" \
  || bad "T46b --source: 'Source:' → path, as written" "exit $rc · stdout '$out' · stderr $err"

printf '%s\n' '# 工单' '' '模板长这样:' '' '```' '来源:<审查回信的路径>' 'Source: review.md' '```' >"$T/o47.md"
run_check --source "$T/o47.md"
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "T47 --source: 来源 only inside a fence → nothing" \
  || bad "T47 --source: 来源 only inside a fence → nothing" "exit $rc · stdout '$out' · stderr $err"

printf '%s\n' '# 工单' '' '来源:<审查回信的路径>' >"$T/o48.md"
run_check --source "$T/o48.md"
expect "T48 --source: placeholder → 1" 1 "来源:<审查回信的路径>"

printf '%s\n' '# 工单' '' 'Source:   ' >"$T/o48b.md"
run_check --source "$T/o48b.md"
expect "T48b --source: empty → 1" 1 "review source line"

run_check --source "$T/o6.md"
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "T49 --source: no 来源 → nothing, exit 0" \
  || bad "T49 --source: no 来源 → nothing, exit 0" "exit $rc · stdout '$out' · stderr $err"

# --- dispatch gate ------------------------------------------------------------
# station-b is idle in ledger.example.json. Dispatch runs from $T/d, where review.md is
# a copy of review3.md — so the orders' "来源:review.md" names it.
setup_dispatch() {
  rm -rf "$T/d"; mkdir -p "$T/d/stations/station-b"
  cp "$ROOT/ledger.example.json" "$T/d/ledger.json"
  cp "$T/d/ledger.json" "$T/d/ledger.before"
  cp "$T/review3.md" "$T/d/review.md"
  cp "$T/review3.md" "$T/d/other-review.md"
}
run_dispatch() {  # run_dispatch <order> [dispatch args…]
  local o="$1"; shift
  rc=0
  ( cd "$T/d" && AGENT_CMD=echo STATIONS_DIR="$T/d/stations" LEDGER="$T/d/ledger.json" \
      LOGS="$T/d/logs" "$DISPATCH" station-b "$o" --fg "$@" ) \
    >"$T/out" 2>"$T/err" || rc=$?
  out="$(cat "$T/out")"; err="$(cat "$T/err")"
}
logs_empty() { [ ! -d "$T/d/logs" ] || [ -z "$(ls -A "$T/d/logs")" ]; }
station_state() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["agents"]["station-b"]["state"])' "$T/d/ledger.json"
}
# refused <name> <text stderr must contain>
refused() {
  if [ "$rc" -eq 0 ]; then bad "$1" "exit 0 · $out"
  elif ! cmp -s "$T/d/ledger.before" "$T/d/ledger.json"; then bad "$1" "ledger changed"
  elif ! logs_empty; then bad "$1" "files in LOGS: $(ls -A "$T/d/logs")"
  elif ! grep -qF -- "$2" <<<"$err"; then bad "$1" "stderr lacks '$2' · stderr: $err"
  else ok "$1 (exit $rc, ledger byte-identical, no logs)"; fi
}
dispatched() {
  if [ "$rc" -ne 0 ]; then bad "$1" "exit $rc · $err"
  elif [ "$(station_state)" != "running" ]; then bad "$1" "state is $(station_state)"
  else ok "$1 (station-b running)"; fi
}

# T8 refuse: the transcription misses B2
setup_dispatch
run_dispatch "$T/o2.md" --from-review review.md
refused "T8 dispatch refuses a transcription that misses B2" "missing B2"

# T9 allow: same file, spelled differently
setup_dispatch
run_dispatch "$T/o1.md" --from-review "$T/d/./review.md"
dispatched "T9 dispatch allows"

setup_dispatch
run_dispatch "$T/o1.md"
refused "T50 order names a source, no --from-review" \
  "order names a review source (review.md) but --from-review was not given. Nothing dispatched."

setup_dispatch
run_dispatch "$T/o1.md" --from-review other-review.md
refused "T51 --from-review names another file" "is not the file given to --from-review"

setup_dispatch
rm "$T/d/review.md"
run_dispatch "$T/o1.md" --from-review other-review.md
refused "T52 the order's source does not exist" "does not exist"

setup_dispatch
run_dispatch "$T/o48.md"
refused "T53 source line is still the placeholder" "review source line"

setup_dispatch
run_dispatch "$T/o47.md"
dispatched "T54 来源 only inside a fence, no --from-review"

# an order with no source and no --from-review dispatches as it always did — even
# one that would fail the check
printf '%s\n' '# 工单' '' '- B1 → 修:x' >"$T/o55.md"
setup_dispatch
run_dispatch "$T/o55.md"
dispatched "T14 no source, no --from-review: unchanged, no gate"

# no source, but --from-review given: the check still runs
setup_dispatch
run_dispatch "$T/o55.md" --from-review review.md
refused "T14b no source, --from-review given: still checked" "missing B2"

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
