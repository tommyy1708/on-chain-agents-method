---
status: NEW
from: review
blockers: B1, B2
---

# 复审回信:D1 返工 2(mech/d1-transcription @f4ec6db)

## Verdict

**有 blocker(2 条)。** 回信一侧(`blockers:` 清单 + 严格标题互核)这轮没打穿,属实;两个口子都在另外两侧:闸门的**触发**(B1)和返工单的**占位符**(B2)。两条都是实测:一张漏了 B2 的返工单,dispatch 退出 0,账本里 station-b 变成 `running`。

## 三值

- 分支:`origin/mech/d1-transcription` → `f4ec6db`(父提交 `d16f6fb` → `d5bb229`),与工单一致。
- 待审范围:`git diff --stat d5bb229 f4ec6db`

```
 scripts/check-transcription.sh    | 120 +++++++++----
 scripts/dispatch.sh               |  19 ++-
 templates/review-order.md         |   6 +-
 templates/review-order.zh.md      |   6 +-
 templates/work-order.md           |   2 +
 templates/work-order.zh.md        |   2 +
 tests/check-transcription.test.sh | 350 +++++++++++++++++++++++++-------------
 7 files changed, 346 insertions(+), 159 deletions(-)
```

- 我自己跑的全量(在 f4ec6db 上,沙箱里 `mktemp` 用 PATH 垫片指到 `$TMPDIR`):

```
$ bash .scratch/run-suite.sh base
exit=0
73 passed, 0 failed
```

与枢纽的 73/0 一致。

---

## Blockers

### B1 · 闸门的触发只认一种写法,别的写法全部放行(fail-open)

**位置**:`scripts/check-transcription.sh:89` `SOURCE = re.compile(r"^(来源|Source)\s*[:：]\s*(.*)$")`;`scripts/dispatch.sh:79-86`。

**跟已知 #1、#2 的关系**:根因相同(闸门要不要跑,取决于在正文里「认出」一行字,认不出就当没有,整个闸门都不跑),**但输入不一样,修 #1(围栏)也修不好这一条**。如果枢纽认为这和 #1 是同一条,合并也行;只是下一轮返工只修围栏的话,这里还是开着的。

**复现**:返工单漏了 B2(只交代 B1、B3),来源行换成别的写法,dispatch 时**不带** `--from-review`。审查回信是 `blockers: B1, B2, B3`,三个严格标题都在。脚本是 `.scratch/probe.sh` 的 A 段(收尾时已删,关键输入都在下面)。

```
--- A1  source line: 来源:review.md                      ← 对照:按模板写
[A1 --source] exit=0
review.md
[A1 dispatch, no --from-review] exit=1 station-b=idle
dispatch: order names a review source (review.md) but --from-review was not given. Nothing dispatched.
--- A2  source line: **来源**:review.md
[A2 --source] exit=0

[A2 dispatch, no --from-review] exit=0 station-b=running
dispatched  station=station-b  order=/tmp/claude-501/probe/a2.md  pid=1043
--- A3  source line: **来源:** review.md
[A3 dispatch, no --from-review] exit=0 station-b=running
--- A4  source line: - 来源:review.md
[A4 dispatch, no --from-review] exit=0 station-b=running
--- A5  source line: source: review.md
[A5 dispatch, no --from-review] exit=0 station-b=running
--- A6  source line:  来源:review.md          (行首一个空格)
[A6 dispatch, no --from-review] exit=0 station-b=running
--- A7  source line: > 来源:review.md
[A7 dispatch, no --from-review] exit=0 station-b=running
--- A8  source line: 审查来源:review.md
[A8 dispatch, no --from-review] exit=0 station-b=running
--- A9  source line: 来源 / Source:review.md
[A9 dispatch, no --from-review] exit=0 station-b=running
```

(A3–A9 的 `--source` 输出都是 `exit=0` 加一个空行,dispatch 输出都和 A2 一样是 `dispatched  station=station-b …`;上面省掉了重复的行,没删掉任何不一样的输出。)

**为什么是 blocker**:工单问的是「还有没有别的办法让一张漏交代的返工单派出去」,A2–A7 这几种都是认真写的人很自然会写出来的(加粗标签、列表项、放进引用块、IME 顺手打的小写),而且结果是**悄悄放行**,不是报错拦下。返工单上的 `- Bn → ` 行明明是 check 能准确解析的,可闸门只看来源行认不认得出。

**方向(不是修法,枢纽定)**:回信一侧这轮就是把「猜标题」换成了「声明 + 互核」;触发一侧还在猜。比如让「工单里有任何一行 `- Bn → 修/不修/fix/not fixing`」也要求带 `--from-review`,这是 check 本来就在精确解析的格式,不靠来源行认不认得出。这一条跟 T14 钉住的「没来源、没 flag → 照旧派」是冲突的,要人拍板。

### B2 · 占位符只拦「整条完全等于」清单里那几个词,稍微多一个字就当已交代

**位置**:`scripts/check-transcription.sh:95` `PLACEHOLDER = re.compile(r"^(<[^<>]*>|[.…]+|(?i:tbd|todo)|待补|待定)$")`。

**复现**:审查回信 `blockers: B1, B2, B3`;返工单 `来源:review.md`,B1、B3 正常,**B2 的正文**依次换成下面这些。每一种的输出都一字不差是同一行:

```
B2 的正文(依次):U+200B 零宽空格 | U+2060 | TBD. | TODO: 转写 | 待补充 | (待补) | 【待定】 | — | - | ？ | <转写后的要求>。 | xxx | N/A

每一种:
[B] exit=0
check-transcription: ok · 3 blockers · 3 fix · 0 not fixing
```

也就是说,B2 实际上没交代,check 却把它算成 `3 fix`,dispatch 会放行(带了 `--from-review` 也一样)。

**为什么是 blocker**:按工单的判据,这就是「漏交代的返工单派出去」,在返工单一侧。`待补充`、`TODO: 转写`、`<转写后的要求>。`(模板占位符后面多打了一个句号)是手写的时候真会出现的;零宽字符那两个是凑出来的,放在这里只是说明判据是「整条完全相等」。

**说明**:这和回信一侧上一轮的处境一样,是「靠猜」的:词表永远列不全。如果人判定这是可接受的限度(像已知 #5 那样写进设计里),这条可以降级;但那得是人拍板,不是默认。

---

## 刀验(我打的 7 把,都跟站位的 11 把、枢纽的 4 把不同)

每把都是在已提交代码上原地改、跑**全量**、`git checkout -- <文件>` 还原,还原后 `git diff --stat` 为空(每把的输出最后一行都是 `restored; git diff after restore: <empty>`)。

| 刀 | 改动(看着像对的) | 结果 | 确切失败信息 |
|---|---|---|---|
| K1 | dispatch 比路径时 `os.path.realpath` → `os.path.abspath` | **在 /tmp 下红,换个没有软链接的 TMPDIR 就全绿** | 见下 |
| K2 | `SOURCE` 的 `[:：]` → 只认半角 `:` | **全绿,活下来了** | `exit=0` / `73 passed, 0 failed` |
| K3 | `ENTRY` 行首 `^- ` → `^\s*- `(允许缩进) | **全绿,活下来了** | `exit=0` / `73 passed, 0 failed` |
| K4 | 标题/清单互核 `if listed is not None:` → `if listed:` | 红 1 | `FAIL  T6c blockers: none + one strict heading — exit 0, wanted 1 · stderr: ` / `72 passed, 1 failed` |
| K5 | dispatch:认出来源之后就跳过 check(`if [ -n "$REVIEW" ] && [ -z "$source_path" ]`) | 红 1 | `FAIL  T8 dispatch refuses a transcription that misses B2 — exit 0 · dispatched  station=station-b  order=/tmp/claude-501/tmp.2jzt4w/o2.md  pid=3864` / `72 passed, 1 failed` |
| K6 | dispatch:`--source` 读失败时吞掉(`2>/dev/null) \|\| source_path=""`) | 红 1 | `FAIL  T53 source line is still the placeholder — exit 0 · dispatched  station=station-b  order=/tmp/claude-501/tmp.cbcDfh/o48.md  pid=4508` / `72 passed, 1 failed` |
| K7 | `--source` 不跳过围栏(逐行读整份文件) | 红 2 | `FAIL  T47 --source: 来源 only inside a fence → nothing — exit 1 · stdout '' · stderr check-transcription: review source line is not filled in: 来源:<审查回信的路径>` 和 `FAIL  T54 来源 only inside a fence, no --from-review — exit 1 · check-transcription: review source line is not filled in: 来源:<审查回信的路径>` / `71 passed, 2 failed` |

K1 两次运行:

```
# TMPDIR=/tmp/claude-501(/tmp 是指向 /private/tmp 的软链接)
exit=1
FAIL  T9 dispatch allows — exit 1 · dispatch: order's review source (review.md) is not the file given to --from-review (/tmp/claude-501/tmp.l6c4KU/d/./review.md). Nothing dispatched.
72 passed, 1 failed

# TMPDIR=/Users/laoniu/work/stations/review/.scratch/tmp(realpath == 自身:True)
exit=0
73 passed, 0 failed
# 同一个 TMPDIR 下不加刀的基线:exit=0 / 73 passed, 0 failed
```

⇒ T9 能拦住 K1,只是碰巧沾了 macOS `/tmp` 软链接的光;在没有软链接的机器上(比如 Linux CI)`realpath` 这个要求没有测试守着。K2、K3 的解读放在 Should-fix 里。

K1 的完整 diff(另外六把形状相同,都是一行,改动内容见上表):

```diff
--- a/scripts/dispatch.sh
+++ b/scripts/dispatch.sh
@@ -80,7 +80,7 @@
-  realpath_of() { python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
+  realpath_of() { python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$1"; }
```

---

## Should-fix(不编号)

- **S-a · 全角冒号的来源行没有测试(K2 活下来了)**。现在的代码是认的,实测:`来源：review.md` → `--source` 输出 `review.md`、`exit=0`。可一旦有人把它「简化」成只认半角,全量照样 73/0。中文输入法默认打全角冒号,真这么改了就是 B1 那种悄悄放行。
- **S-b · T9 没有真正守住 `realpath`(K1)**。要加一个 `--from-review` 用软链接指向同一个文件的用例,不能靠 `/tmp`。
- **S-c · 没有测试钉住「交代行必须顶格」(K3)**。放开以后,缩进 4 格的那种代码块示例也会被当成交代。
- **S-d · 误拦:中文标点写的清单**。都是 `exit=1`,响亮地拦下来,但人是按模板认真写的:

```
blockers: B1、B2    → check-transcription: review reply blockers line unreadable: blockers: B1、B2
blockers: B1，B2    → check-transcription: review reply blockers line unreadable: blockers: B1，B2
blockers: B1, B2,   → check-transcription: review reply blockers line unreadable: blockers: B1, B2,
blockers: 无        → check-transcription: review reply blockers line unreadable: blockers: 无
```

  模板只给了一个半角逗号的例子,没说「只能用半角逗号」。要么模板写明,要么把 `、`、`,` 也认上。
- **S-e · 误拦:要求写在下一行的交代**:

```
- B1 → 修:
  空输入返回错误(续行写要求)
→ check-transcription: B1: empty entry
```

- **S-f · 报错会误导**。交代行写得差一点(`- B1 → 修 :x`、`- B2 →修:y`、`- B3 -> 修:z`、`* B1 →`、`1. B2 →`、`- **B3** →`、`修复:`、`Fix:`),都报 `missing B1 / missing B2 / missing B3`。可 B1 那一行明明在,枢纽会去找一行已经在那儿的东西。能不能在「某行提到了 Bn、但格式不对」的时候提示一句。
- **S-g · 误拦:来源路径的写法**(dispatch 都带了 `--from-review review.md`,返工单是完整的):

```
来源:`review.md`              → dispatch: review source named in the order does not exist: `review.md`. Nothing dispatched.
来源:[审查回信](review.md)    → dispatch: review source named in the order does not exist: [审查回信](review.md). Nothing dispatched.
来源:Review.md                → dispatch: order's review source (Review.md) is not the file given to --from-review (review.md). Nothing dispatched.
来源:review.md(第二轮)        → dispatch: review source named in the order does not exist: review.md(第二轮). Nothing dispatched.
来源:to-hub/2026-09-19-x-review.md  (照着 reply: 字段的写法,相对 mailbox/;在协调根目录跑 dispatch)
                              → dispatch: review source named in the order does not exist: to-hub/2026-09-19-x-review.md. Nothing dispatched.
```

  最后一种最容易踩:工单的 `reply:` 是相对 `mailbox/` 的,来源行却是相对**跑 dispatch 的当前目录**。这一点只写在 `dispatch.sh` 的头注释里,模板里没有。`Review.md` 那一种在 macOS(大小写不敏感)上其实是同一个文件,报错却说「不是同一个文件」。

## Nit

- `--from-review --source`:返工单没有来源行、而且漏了 B2 时,`dispatch … --from-review --source` → `exit=0 station-b=running`。因为 `"$CHECK" "$REVIEW" "$ORDER"` 变成了 `check --source <工单>`。没人会这么敲,记一笔而已。

## 新模板好不好用(写这封回信时的实际感受)

- 「最后回头填 `blockers:`」这条可以照做,但 frontmatter 在文件最上面,写完再滚回去填,很容易忘。我这封是写完之后用 check 自检才放心的(自检输出见下)。模板可以建议「写完跑一次 check 自检」。
- 清单里的逗号,我第一反应是用中文 `、`;要不是先测过 S-d,我自己也会被拦。
- 标题里的 `·`(U+00B7),我是从模板里复制的;中文输入法打出来的是它,日文输入法打的 `・`、或者 `•` 都不对(会响亮地拦下来,不会漏)。
- 回信里要引用标题格式做例子,只能放进围栏。我在正文里有几处提到 `### Bn · `,都是用行内代码写在行中间,不在行首,所以没事。模板可以点明一句「行首的 `### B` 只能是真的 blocker」。
- frontmatter 里要写哪几个字段,模板只说了和 `status:`、`from:` 并列,`needs:`/`reply:` 要不要带没说;我只写了三个。
- 我的班次提示词要求结尾那一节叫 'found but not done',工单模板叫「我发现但没做的事」。两个名字,不知道该用哪个;我用了前者。

**自检**:这封回信的草稿(和本文件 blocker 部分相同)跑 check,配一张完整交代 B1、B2 的草稿返工单,再配一张故意漏掉 B2 的对照:

```
$ scripts/check-transcription.sh <本回信> order-full.md
check-transcription: ok · 2 blockers · 1 fix · 1 not fixing
exit=0
$ scripts/check-transcription.sh <本回信> order-miss.md
check-transcription: missing B2
exit=1
```

---

## 收尾

```
$ git -C /Users/laoniu/work/stations/review switch --detach origin/main
Previous HEAD position was f4ec6db scripts: blockers manifest is authoritative; dispatch requires --from-review for sourced orders (D1 rework 2)
HEAD is now at 1e226dd Merge pull request #1 from tommyy1708/sync/process-truth-and-permissions
$ git -C /Users/laoniu/work/stations/review checkout -- .
$ rm -rf /Users/laoniu/work/stations/review/.scratch /tmp/claude-501/probe
$ git status --short --ignored
!! CLAUDE.md
```

`git status --short` 为空;加 `--ignored` 只剩工位自己的 `CLAUDE.md`(开工前就有,不是我留的)。被审分支没动过:我的所有改动都在自己的克隆里,每把刀之后都还原了。

## found but not done

- 上面 B1、B2、S-a 到 S-g、Nit:都只报,没修(我对被审分支零写权限,也不该修)。
- **没有测的**:Linux 上的行为。K1「在没有软链接的机器上会活下来」是在 macOS 上换一个不含软链接的 TMPDIR 模拟出来的,没有在真的 Linux 上跑。
- **没有测的**:真实协调目录上的端到端派单。我所有的 dispatch 都跑在 `$TMPDIR` 下的临时账本(`ledger.example.json` 的副本)和 `AGENT_CMD=echo` 上,没有碰真账本,也没有起真的 agent。
- **没有展开的**:协议要求处理完的回信归档到 `archive/`。如果枢纽先归档再派返工单,来源路径就失效,会被拦(属于响亮的那一种,我从代码推断的,**没实测**)。归档和派单的先后顺序,可能要在 PROTOCOL 里写一句。
- 已知清单(#1–#5)我都没有重复去测。
- 探针 B 段的输出标签在我的日志里是乱码(`printf %q` 把多字节字符转义了);上面列的输入是脚本里的原样输入,输出行是日志原文。
