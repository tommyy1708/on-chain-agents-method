#!/usr/bin/env bash
#
# check-transcription.test.sh — tests for scripts/check-transcription.sh, for the
# "review:" gate in scripts/dispatch.sh, and for the ledger dispatch.sh writes.
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
    printf -- '---\nstatus: NEW\nfrom: hub\nreview: to-hub/x-review.md\n---\n\n# 返工\n\n## 审查结论逐条交代\n\n'
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

# separators: half-width comma, full-width comma, 、 (D1 rework 3)
order "$T/o64.md" "- B1 → 修:x" "- B2 → 修:y"
i=0
for m in 'B1、B2' 'B1,B2' 'B1，B2' 'B1 ， B2'; do
  i=$((i + 1))
  review "$T/review-sep$i.md" "$m" '### B1 · a' '### B2 · b'
  run_check "$T/review-sep$i.md" "$T/o64.md"
  expect "T64.$i blockers: $m" 0
done

review "$T/review-wu.md" "无" '## Blocker' '' '无。'
run_check "$T/review-wu.md" "$T/o6.md"
expect "T65 blockers: 无 is none" 0

review "$T/review-trail.md" "B1, B2," '### B1 · a' '### B2 · b'
run_check "$T/review-trail.md" "$T/o64.md"
expect "T66 blockers: B1, B2, (trailing comma)" 1 "review reply blockers line unreadable: blockers: B1, B2,"

review "$T/review-trail2.md" "B1、B2、" '### B1 · a' '### B2 · b'
run_check "$T/review-trail2.md" "$T/o64.md"
expect "T66b blockers: B1、B2、 (trailing 、)" 1 "unreadable"

# an entry must start at the beginning of the line (S-c)
review "$T/review12.md" "B1, B2" '### B1 · a' '### B2 · b'
order "$T/o67.md" "  - B1 → 修:x" "- B2 → 修:y"
run_check "$T/review12.md" "$T/o67.md"
expect "T67 indented entry is not an entry" 1 "missing B1"

# a line that mentions Bn in the wrong format is named in the error (S-f)
order "$T/o68.md" "- B1 -> 修:x" "- B2 → 修:y"
run_check "$T/review12.md" "$T/o68.md"
ln=$(grep -n -- '- B1 -> ' "$T/o68.md" | cut -d: -f1)
expect "T68 ASCII arrow: missing B1, and the line is named" 1 "missing B1 (line $ln mentions B1 but is not in the \"- B1 → 修:…\" format)"

# whole word only: B10 is not B1; and a hint never turns a pass into a failure
order "$T/o69.md" "B10 另说。" "- B2 → 修:y"
run_check "$T/review12.md" "$T/o69.md"
[ "$rc" -eq 1 ] && grep -qxF "check-transcription: missing B1" <<<"$err" \
  && ok "T69 B10 does not count as a mention of B1" || bad "T69 B10 does not count as a mention of B1" "exit $rc · stderr: $err"

order "$T/o69b.md" "B1 和 B2 的共同根因。" "- B1 → 修:x" "- B2 → 修:y"
run_check "$T/review12.md" "$T/o69b.md"
expect "T69b prose mentioning B1 next to a real entry" 0

# the hint names the entry line that was written wrong, not the first line that happens to
# mention Bn — in the benchmark it pointed at the front matter's "needs:", where nothing
# was wrong, while the malformed entry sat further down
{
  printf -- '---\nstatus: NEW\nfrom: hub\nneeds: 逐条交代 B1 与 B2\nreview: to-hub/x-review.md\n---\n\n# 返工\n\n'
  printf '%s\n' '- B1 -> 修:空输入返回错误' '- B2 → 修:y'
} >"$T/o70a.md"
run_check "$T/review12.md" "$T/o70a.md"
ln=$(grep -n -- '- B1 -> ' "$T/o70a.md" | cut -d: -f1)
expect "T70a hint points at the malformed entry line, not the front matter's needs:" 1 \
  "missing B1 (line $ln mentions B1 but is not in the \"- B1 → 修:…\" format)"

# no line looks like an entry: fall back to the first mention, as before
{
  printf -- '---\nstatus: NEW\nfrom: hub\nneeds: 逐条交代 B1 与 B2\nreview: to-hub/x-review.md\n---\n\n# 返工\n\n'
  printf '%s\n' 'B1 的根因是没有校验输入。' '- B2 → 修:y'
} >"$T/o70b.md"
run_check "$T/review12.md" "$T/o70b.md"
ln=$(grep -n -- 'needs: ' "$T/o70b.md" | cut -d: -f1)
expect "T70b no entry-like line: hint falls back to the first mention" 1 \
  "missing B1 (line $ln mentions B1 but is not in the \"- B1 → 修:…\" format)"

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

order "$T/o40.md" "- B1 → 修:……" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o40.md"
expect "T40 修:……" 1 "B1: placeholder not filled"

order "$T/o41.md" "- B1 → 修:x" "- B2 → 修:y" "- B3 → 修:。。。不是占位,是内容"
run_check "$T/review3.md" "$T/o41.md"
expect "T41 text after dots is real content" 0

# not one letter, digit or Han character (D1 rework 3)
i=0
for c in $'​' '—' '-' '?' '？' '……'; do
  i=$((i + 1))
  order "$T/o60-$i.md" "- B1 → 修:$c" "- B2 → 修:y" "- B3 → 修:z"
  run_check "$T/review3.md" "$T/o60-$i.md"
  expect "T60.$i 修:$(printf %s "$c" | od -An -tx1 | tr -d ' \n') — no letter, digit or Han" 1 "B1: placeholder not filled"
done

# the template's placeholder with something added is still the placeholder
order "$T/o61.md" "- B1 → 修:<转写后的要求>。" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o61.md"
expect "T61 修:<转写后的要求>。" 1 "B1: placeholder not filled"

# every entry placeholder in the four templates, read from the templates, not copied
review "$T/review1.md" "B1" '### B1 · one'
n=0
for tpl in work-order.md work-order.zh.md review-order.md review-order.zh.md; do
  while IFS= read -r line; do
    n=$((n + 1))
    order "$T/o62-$n.md" "$(sed -E 's/^- B[0-9]+ /- B1 /' <<<"$line")"
    run_check "$T/review1.md" "$T/o62-$n.md"
    expect "T62.$n $tpl: '$line'" 1 "B1: placeholder not filled"
  done < <(grep -E '^- B[0-9]+ → ' "$ROOT/templates/$tpl")
done
[ "$n" -ge 4 ] && ok "T62 found $n entry placeholders in the templates" \
  || bad "T62 entry placeholders in the templates" "found only $n"

# known limit: a to-do written in words is taken as accounted for. The human decided the
# gate only checks that something was written; guessing words never ends.
for c in '待补充' 'N/A' 'TODO: 转写' 'TBD' '待定'; do
  order "$T/o63.md" "- B1 → 修:$c" "- B2 → 修:y" "- B3 → 修:z"
  run_check "$T/review3.md" "$T/o63.md"
  expect "T63 known limit: 修:$c passes" 0
done

# a placeholder in `inline code` is being talked about, not left unfilled (D1 rework 4, S2)
order "$T/o46.md" '- B1 → 修:把模板里的 `<转写后的要求>` 改成 `<要求原文>`' "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o46.md"
expect "T46 placeholder quoted in inline code, with words around it" 0

# … unless the inline code is all there is
order "$T/o47.md" '- B1 → 修:`<转写后的要求>`' "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o47.md"
expect "T47 修:\`<转写后的要求>\` — nothing but inline code" 1 "B1: placeholder not filled"

# known cost: a placeholder quoted WITHOUT backticks is still taken as unfilled
order "$T/o48.md" "- B1 → 修:照 <转写后的要求> 改" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o48.md"
expect "T48 known cost: 修:照 <转写后的要求> 改 (no backticks) is refused" 1 "B1: placeholder not filled"

# digits alone are content
order "$T/o49.md" "- B1 → 修:42" "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o49.md"
expect "T49 修:42 — digits only" 0

# backticks on both sides of a placeholder do not wrap it: it is still left in (D1 rework 5, M1).
# Words after the last backtick too, so one span from the first backtick to the last would
# not leave "nothing but inline code" behind.
order "$T/o50.md" '- B1 → 修:`x` 照 <转写后的要求> 改 `y` 就行' "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o50.md"
expect "T50 修:\`x\` 照 <转写后的要求> 改 \`y\` 就行 — placeholder between two code spans" 1 "B1: placeholder not filled"

# an entry that is nothing but inline code, and no placeholder in it, is filled in (M2)
order "$T/o51.md" '- B1 → 修:`retry=3`' "- B2 → 修:y" "- B3 → 修:z"
run_check "$T/review3.md" "$T/o51.md"
expect "T51 修:\`retry=3\` — only inline code, not a placeholder" 0

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
# The real review that started D1, against the real transcription of it (the order now
# declares its review in front matter, as every order must). Old format: no manifest. It
# is no longer accepted, and this pins that.
run_check "$ROOT/tests/fixtures/review-2026-09-19-d1.md" "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-1.md"
expect "T30 real regression, old format (no blockers: line)" 1 'review reply has no "blockers:" line in its front matter'

# the same reply with one line added to its front matter
awk 'NR == 2 { print "blockers: B1, B2, B3" } { print }' "$ROOT/tests/fixtures/review-2026-09-19-d1.md" >"$T/review-d1.md"
run_check "$T/review-d1.md" "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-1.md"
expect "T30b real regression + 'blockers: B1, B2, B3'" 0
grep -qF 'ok · 3 blockers · 3 fix · 0 not fixing' <<<"$out" \
  && ok "T30b counts" || bad "T30b counts" "stdout: $out"

# The hub's own rework-3 order against the rework-2 review it transcribed (both from the
# archive, the hub's closing note removed; the order given the review: line it lacked).
# Its B2 line quotes `<转写后的要求>。` in inline code, and was refused as unfilled.
run_check "$ROOT/tests/fixtures/review-2026-09-19-d1-rework-2.md" "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-3.md"
expect "T30c real regression: rework-3 order vs rework-2 review" 0
grep -qF 'ok · 2 blockers · 2 fix · 0 not fixing' <<<"$out" \
  && ok "T30c counts" || bad "T30c counts" "stdout: $out"

# --- --review-path --------------------------------------------------------------
# review_path_ok <name> <order> <expected stdout>
review_path_ok() {
  run_check --review-path "$2"
  [ "$rc" -eq 0 ] && [ "$out" = "$3" ] && ok "$1" || bad "$1" "exit $rc · stdout '$out' · stderr $err"
}
fm() {  # fm <file> <front matter lines…> — a front matter, then a body
  local f="$1"; shift
  { echo '---'; printf '%s\n' "$@"; printf -- '---\n\n# 工单\n\n改名。\n'; } >"$f"
}

review_path_ok "T70 review: to-hub/x-review.md → the path" "$T/o1.md" "to-hub/x-review.md"

fm "$T/o71.md" 'status: NEW' 'review: none'
review_path_ok "T71 review: none → none" "$T/o71.md" "none"
fm "$T/o71b.md" 'status: NEW' 'review: None'
review_path_ok "T71b review: None → none" "$T/o71b.md" "none"

fm "$T/o72.md" 'status: NEW' 'from: hub'
run_check --review-path "$T/o72.md"
expect "T72 no review: line" 1 'order has no "review:" line in its front matter (write "review: none" if this is not a rework order)'

printf '%s\n' '# 工单' '' 'review: to-hub/x-review.md' >"$T/o73.md"
run_check --review-path "$T/o73.md"
expect "T73 no front matter, review: in the body" 1 'order has no "review:" line in its front matter'

fm "$T/o74.md" 'status: NEW' 'review: none' 'review: to-hub/x-review.md'
run_check --review-path "$T/o74.md"
expect "T74 two review: lines" 1 'order has two "review:" lines'

fm "$T/o75.md" 'status: NEW' 'review:   '
run_check --review-path "$T/o75.md"
expect "T75 review: empty" 1 "order's review: line is not filled in: review:"

# the placeholder in each of the two work-order templates, read from the template
for tpl in work-order.md work-order.zh.md; do
  line=$(grep -m1 '^review:' "$ROOT/templates/$tpl" || true)
  fm "$T/o76.md" 'status: NEW' "$line"
  run_check --review-path "$T/o76.md"
  if [ -z "$line" ]; then bad "T76 $tpl: review: placeholder" "the template has no review: line"
  else expect "T76 $tpl: '$line'" 1 "order's review: line is not filled in: $line"; fi
done

# a review order is never a rework order: its templates say "review: none", literally (D1 rework 4, S3)
for tpl in review-order.md review-order.zh.md; do
  line=$(grep -m1 '^review:' "$ROOT/templates/$tpl" || true)
  fm "$T/o77.md" 'status: NEW' "$line"
  review_path_ok "T77 $tpl: '$line' → none" "$T/o77.md" "none"
done

# review: none, but a filled-in entry line: the order answers a review it does not name (S1)
fm "$T/o78.md" 'status: NEW' 'review: none'
printf '%s\n' '## 审查结论逐条交代(仅返工单)' '' '- B1 → 修:x' >>"$T/o78.md"
run_check --review-path "$T/o78.md"
ln=$(grep -n -- '- B1 → ' "$T/o78.md" | cut -d: -f1)
expect "T78 review: none + a filled-in '- B1 → 修:x'" 1 \
  "order says \"review: none\" but line $ln accounts for B1: declare the review it answers"

# review: none on a work-order template filled in as an ordinary order, its rework section
# left as the template has it — the entry placeholders are not accounting for anything
for tpl in work-order.md work-order.zh.md; do
  sed 's/^review:.*/review: none/' "$ROOT/templates/$tpl" >"$T/o79-$tpl"
  if ! grep -qE '^- B[0-9]+ → ' "$T/o79-$tpl"; then bad "T79 $tpl" "the template has no entry lines"; continue; fi
  review_path_ok "T79 $tpl as-is, review: none, placeholder entries → none" "$T/o79-$tpl" "none"
done

# review: none, and an unclosed fence above filled-in entries: the fence hides them (D1 rework 5, B1)
fm "$T/o78b.md" 'status: NEW' 'review: none'
printf '%s\n' 'Run this:' '```' 'make test' '' '## 审查结论逐条交代(仅返工单)' '' \
  '- B1 → 修:空输入返回错误' '- B2 → 不修:上游已脱敏' >>"$T/o78b.md"
run_check --review-path "$T/o78b.md"
ln=$(grep -n -- '^```$' "$T/o78b.md" | cut -d: -f1)
expect "T78b review: none + an unclosed fence above filled-in entries" 1 \
  "order says \"review: none\" but has an unclosed code fence opened at line $ln; close it so its entry lines can be checked"

# review: None is none — a filled-in entry is still caught (M3)
fm "$T/o78c.md" 'status: NEW' 'review: None'
printf '%s\n' '- B1 → 修:x' >>"$T/o78c.md"
run_check --review-path "$T/o78c.md"
expect "T78c review: None + a filled-in '- B1 → 修:x'" 1 "accounts for B1: declare the review it answers"

# "not fixing" accounts for a blocker too (M4)
fm "$T/o78d.md" 'status: NEW' 'review: none'
printf '%s\n' '- B1 → 不修:上游已脱敏' >>"$T/o78d.md"
run_check --review-path "$T/o78d.md"
expect "T78d review: none + only '- B1 → 不修:上游已脱敏'" 1 "accounts for B1: declare the review it answers"

# an entry line shown as an example inside a code block is not an entry
fm "$T/o78e.md" 'status: NEW' 'review: none'
printf '%s\n' '交代行长这样:' '```' '- B1 → 修:空输入返回错误' '```' >>"$T/o78e.md"
review_path_ok "T78e review: none + an entry line inside a code block → none" "$T/o78e.md" "none"

# --- dispatch gate ------------------------------------------------------------
# station-b is idle in ledger.example.json. Dispatch runs from $T/d with MAILBOX=$T/d/mailbox,
# where to-hub/x-review.md is a copy of review3.md — so the orders' "review: to-hub/x-review.md"
# names it. Nothing named to-hub/ exists in $T/d itself.
setup_dispatch() {
  rm -rf "$T/d"; mkdir -p "$T/d/stations/station-b" "$T/d/mailbox/to-hub"
  cp "$ROOT/ledger.example.json" "$T/d/ledger.json"
  cp "$T/d/ledger.json" "$T/d/ledger.before"
  cp "$T/review3.md" "$T/d/mailbox/to-hub/x-review.md"
}
run_dispatch() {  # run_dispatch <order> [dispatch args…]
  local o="$1"; shift
  rc=0
  ( cd "$T/d" && AGENT_CMD=echo STATIONS_DIR="$T/d/stations" LEDGER="$T/d/ledger.json" \
      MAILBOX="$T/d/mailbox" LOGS="$T/d/logs" "$DISPATCH" station-b "$o" --fg "$@" ) \
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

setup_dispatch
run_dispatch "$T/o72.md"
refused "T80 dispatch: order has no review: line" 'order has no "review:" line in its front matter'

setup_dispatch
run_dispatch "$T/o73.md"
refused "T81 dispatch: review: in the body, not the front matter" 'order has no "review:" line in its front matter'

setup_dispatch
run_dispatch "$T/o74.md"
refused "T82 dispatch: two review: lines" 'order has two "review:" lines'

line=$(grep -m1 '^review:' "$ROOT/templates/work-order.zh.md" || true)
fm "$T/o83.md" 'status: NEW' "$line"
setup_dispatch
run_dispatch "$T/o83.md"
refused "T83 dispatch: review: is still the template's placeholder ('$line')" "order's review: line is not filled in"

# review: none dispatches as before, without the gate
fm "$T/o84.md" 'status: NEW' 'review: none'
setup_dispatch
run_dispatch "$T/o84.md"
dispatched "T84 dispatch: review: none, no entry lines"
setup_dispatch
run_dispatch "$T/o71b.md"
dispatched "T84b dispatch: review: None"

# … but not an order that accounts for a blocker (S1)
setup_dispatch
run_dispatch "$T/o78.md"
refused "T84c dispatch: review: none + a filled-in '- B1 → 修:x'" "declare the review it answers"

setup_dispatch
run_dispatch "$T/o79-work-order.zh.md"
dispatched "T84d dispatch: work-order.zh.md as-is, review: none, placeholder entries"

setup_dispatch
run_dispatch "$T/o78b.md"
refused "T84e dispatch: review: none + an unclosed fence above filled-in entries" "has an unclosed code fence opened at line"

setup_dispatch
run_dispatch "$T/o78e.md"
dispatched "T84f dispatch: review: none + an entry line inside a code block"

setup_dispatch
run_dispatch "$T/o1.md"
dispatched "T85 dispatch: review: to-hub/x-review.md, file under \$MAILBOX, order complete"

setup_dispatch
run_dispatch "$T/o2.md"
refused "T86 dispatch: same, order misses B2" "missing B2"

setup_dispatch
rm "$T/d/mailbox/to-hub/x-review.md"
run_dispatch "$T/o1.md"
refused "T87 dispatch: review: names a file that does not exist" "does not exist"

setup_dispatch
run_dispatch "$T/o1.md" --from-review to-hub/x-review.md
refused "T88 dispatch: --from-review was removed" \
  "--from-review was removed: declare the review in the order's front matter (review: <path relative to mailbox/>)"

# the real transcription, in the new format, through dispatch
setup_dispatch
cp "$T/review-d1.md" "$T/d/mailbox/to-hub/2026-09-19-d1-check-script-review.md"
run_dispatch "$ROOT/tests/fixtures/order-2026-09-19-d1-rework-1.md"
dispatched "T89 dispatch: real regression, review: in the order's front matter"

# --- the ledger of a foreground shift -----------------------------------------
# ORPHANED is statusline.sh saying "the ledger says running and the process is gone" —
# i.e. a shift died. A --fg shift that ran to the end must never produce it: that is the
# status display lying about a crash that did not happen, which is this repo's own
# failure mode pointing the other way.
#
# The fake agent does three things a real shift cannot be asked to do: report what the
# ledger said WHILE it was running, block until released, and exit with a chosen status.
cat >"$T/agent.sh" <<'EOF'
#!/usr/bin/env bash
[ -z "${FAKE_SNAP:-}" ] || python3 - "$FAKE_LEDGER" "$FAKE_SNAP" <<'PY'
import json, os, sys
a = json.load(open(sys.argv[1])).get("agents", {}).get("station-b", {})
pid = a.get("pid")
alive = False
if isinstance(pid, int):
    try:
        os.kill(pid, 0)
        alive = True
    except OSError:
        alive = False
open(sys.argv[2], "w").write(f"state={a.get('state')} pid={pid} alive={alive}\n")
PY
if [ -n "${FAKE_GO:-}" ]; then
  while [ ! -f "$FAKE_GO" ]; do sleep 0.05; done
fi
exit "${FAKE_EXIT:-0}"
EOF
chmod +x "$T/agent.sh"

run_shift() {  # run_shift <dispatch args…> — order o84.md, FAKE_* from the caller
  rc=0
  ( cd "$T/d" && AGENT_CMD="$T/agent.sh" STATIONS_DIR="$T/d/stations" \
      LEDGER="$T/d/ledger.json" MAILBOX="$T/d/mailbox" LOGS="$T/d/logs" \
      FAKE_LEDGER="$T/d/ledger.json" "$DISPATCH" station-b "$T/o84.md" "$@" ) \
    >"$T/out" 2>"$T/err" || rc=$?
  out="$(cat "$T/out")"; err="$(cat "$T/err")"
}
statusline() { "$ROOT/scripts/statusline.sh" "$T/d/ledger.json" "$T/d/mailbox/to-hub"; }
station_pid() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["agents"]["station-b"].get("pid",""))' \
    "$T/d/ledger.json"
}

# the shift cannot be recorded after it ends: by then the only pid left to name is the
# dispatcher's own, and it is on its way out
setup_dispatch
rm -f "$T/snap"
FAKE_SNAP="$T/snap" run_shift --fg
snap="$(cat "$T/snap" 2>/dev/null || echo '<nothing: the ledger was not written before the shift>')"
if [ "$rc" -ne 0 ]; then bad "T90 --fg: mid-shift the ledger says running, pid alive" "exit $rc · $err"
elif ! grep -qE '^state=running pid=[0-9]+ alive=True$' <<<"$snap"; then
  bad "T90 --fg: mid-shift the ledger says running, pid alive" "read from inside the shift: $snap"
else ok "T90 --fg: mid-shift the ledger says running, pid alive ($snap)"; fi

setup_dispatch
run_shift --fg
line="$(statusline)"
if [ "$rc" -ne 0 ]; then bad "T91 --fg: a finished shift is not ORPHANED" "exit $rc · $err"
elif grep -qF 'station-b:ORPHANED' <<<"$line"; then
  bad "T91 --fg: a finished shift is not ORPHANED" "statusline: $line"
elif ! grep -qF 'station-b' <<<"$line"; then
  bad "T91 --fg: a finished shift is not ORPHANED" "the shift vanished from the status display: $line"
elif [ "$(station_state)" != "running" ]; then
  bad "T91 --fg: a finished shift is not ORPHANED" \
      "state is $(station_state), so accept.sh has nothing to close out"
else ok "T91 --fg: a finished shift is not ORPHANED ($line)"; fi

# a shift that ran and exited 3 is not an orphan either — it is an entry the hub has to
# close out. The status still has to reach the caller.
setup_dispatch
FAKE_EXIT=3 run_shift --fg
line="$(statusline)"
if [ "$rc" -ne 3 ]; then bad "T92 --fg: a failed shift is not ORPHANED, its status survives" "exit $rc, wanted 3 · $err"
elif grep -qF 'station-b:ORPHANED' <<<"$line"; then
  bad "T92 --fg: a failed shift is not ORPHANED, its status survives" "statusline: $line"
elif [ "$(station_state)" != "running" ]; then
  bad "T92 --fg: a failed shift is not ORPHANED, its status survives" \
      "state is $(station_state): the failed shift left nothing to close out"
else ok "T92 --fg: a failed shift is not ORPHANED, its status survives ($line)"; fi

# background is untouched: the pid in the ledger is the shift's own child, and it is
# alive while the shift runs — which is what makes ORPHANED mean something in the mode
# nobody is watching
setup_dispatch
rm -f "$T/go"
FAKE_GO="$T/go" run_shift
line="$(statusline)"; bgpid="$(station_pid)"
if [ "$rc" -ne 0 ]; then bad "T93 background: the ledger names the shift's own live pid" "exit $rc · $err"
elif grep -qF 'station-b:ORPHANED' <<<"$line"; then
  bad "T93 background: the ledger names the shift's own live pid" "flagged a running shift: $line"
elif ! kill -0 "$bgpid" 2>/dev/null; then
  bad "T93 background: the ledger names the shift's own live pid" "pid $bgpid is not alive mid-shift"
else ok "T93 background: the ledger names the shift's own live pid (pid $bgpid, $line)"; fi
touch "$T/go"
for _ in $(seq 100); do kill -0 "$bgpid" 2>/dev/null || break; sleep 0.05; done

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
