---
status: ACKED
from: hub
needs: 已发令,本班次执行。返工 3:闸门的触发改成工单声明;内容只查「交代了没有」
reply: to-hub/2026-09-19-d1-rework-3.md
review: to-hub/2026-09-19-d1-rework-2-review.md
---

# D1 返工 3:工单用 frontmatter 声明 `review:`;内容规则不再猜词

## 这单从哪来

返工 2(d16f6fb + f4ec6db)复审报了 2 个 blocker,枢纽已复现。回信一侧的「声明 + 互核」站住了(复审回信本身就是第一份新格式回信,闸门读对了);剩下两个 blocker 是同一个病换了地方:**触发一侧在猜来源行,内容一侧在猜占位词**。

**人已拍板**(账本 2026-09-19 11:45 两条 decided):
1. 每张工单 frontmatter 必须有 `review: <路径>` 或 `review: none`,缺了不派;路径和 `reply:` 一样**相对 mailbox/**;dispatch 读到路径就自动跑闸门;**`--from-review` 与「来源:」行机制一起取消**。
2. 闸门只管「交代了没有」:内容至少含一个字母 / 数字 / 汉字,且不含模板里的字面占位文字;**删掉 TBD/TODO/待补/待定 词表**。「待补充」「N/A」这类写法是已知局限,要在测试里钉住。

**已经做过的,别重复**:1c2c67b、2315565、d5bb229、d16f6fb、f4ec6db。在同一分支上继续。回信一侧(清单 + 标题互核)、围栏识别**保留**。

## 要什么

## 审查结论逐条交代(仅返工单)

来源:/Users/laoniu/work/coordination/mailbox/to-hub/2026-09-19-d1-rework-2-review.md

- B1 → 修:闸门要不要跑取决于认不认得出来源行(`**来源**:`、`- 来源:`、`> 来源:`、`source:` 等都认不出,闸门静默不跑)。按人拍板,改成工单 frontmatter 里的 `review:` 声明,缺了就拒派。
- B2 → 修:占位词表只拦完全相等的几个词(`待补充`、`TODO: 转写`、`<转写后的要求>。`、`N/A` 都算已交代)。按人拍板,改成「至少一个字母 / 数字 / 汉字 + 不含模板字面占位文字」,删掉词表,把剩下的写法作为已知局限钉在测试里。

复审的 should-fix 一并处理:S-c(交代行必须顶格)补测试;S-d 清单里的 `、` `,` 也认作分隔符,`blockers: 无` 等同 `none`;S-f「某行提到了 Bn、但格式不对」时,在 `missing Bn` 后面提示是哪一行;S-a / S-b / S-g / nit 随来源行机制一起消失,不用做。

**怎样算完成**:新用例在 f4ec6db 上先红,修完全绿;两个提交;刀全部按预期变红。

## 怎么做(执行方案)

### 第 1 步:先复现

先写新测试,在 f4ec6db 上跑,记下变红的原样输出。

### 第 2 步:模板(**单独一个提交**)

- `templates/work-order.md` / `.zh.md` 与 `templates/review-order.md` / `.zh.md` 的 frontmatter,**四份都加一行**(审查单也是工单,也要声明):
  - 中文:`review: <none,或审查回信的路径(相对 mailbox/,和 reply: 一样)>`
  - 英文:`review: <none, or the review reply's path (relative to mailbox/, like reply:)>`
  - 这是占位符,**不填不能派** —— 逼派单的人明确选一个。
- `work-order*.md` 的逐条交代小节:删掉「来源 / Source」那一行和它下面的说明,换成一句:本小节对照的审查回信,就是 frontmatter 里 `review:` 指向的那一份。
- `review-order*.md` 的「回信」一节补三句:清单用半角逗号、中文逗号或顿号分隔都可以;行首的 `### B` 只能是真的 blocker,要举例就放进围栏;写完可以用 `scripts/check-transcription.sh` 配一张草稿返工单自检一次。

提交信息:`templates: every order declares review: in front matter (D1 rework 3)`

### 第 3 步:脚本与 dispatch(**第二个提交**)

**`check-transcription.sh`**

- **删掉 `--source` 模式。** 新增 `--review-path <工单>`:只看工单**文件开头**的 frontmatter。
  - 没有 frontmatter,或里面没有 `review:` 行 → 退出 1:`order has no "review:" line in its front matter (write "review: none" if this is not a rework order)`
  - 有两行 `review:` → 退出 1:`order has two "review:" lines`
  - 值为空,或是 `<…>` 占位符 → 退出 1:`order's review: line is not filled in: <原文>`
  - 值是 `none`(不区分大小写)→ 打印 `none`,退出 0
  - 其他 → 原样打印路径,退出 0
- **清单**:分隔符认 `,` `,` `、` 和空白;`blockers: 无` 等同 `none`。结尾多一个分隔符仍算读不懂。
- **返工单内容规则**(替换现有的 PLACEHOLDER 词表):
  - 内容为空 → `B1: empty entry`(「不修」照旧报 `not fixing without a reason`)
  - 内容里一个字母 / 数字 / 汉字都没有(比如只有 `—`、`-`、`?`、`……`、零宽字符)→ `B1: placeholder not filled`
  - 内容**包含**模板里任何一个字面占位文字(`<转写后的要求>`、`<理由;谁决定的>`、`<the requirement, as transcribed>`、`<reason; who decided>`)→ `B1: placeholder not filled`
  - 其余一律算已交代。
- **S-f 提示**:报 `missing Bn` 时,如果返工单围栏外有一行提到了 `Bn`(整词),就接在后面:`missing B1 (line 12 mentions B1 but is not in the "- B1 → 修:…" format)`。**只影响报错信息,不影响通过与否。**

**`dispatch.sh`**

- 在写任何东西之前:`review=$("$CHECK" --review-path "$ORDER")`,失败就带着它的报错拒派。
- `review` 是 `none` → 照旧派单,不跑闸门。
- 否则 → 审查回信是 `"$MAILBOX/$review"`(`MAILBOX` 沿用脚本里已有的变量);不存在就拒派;存在就跑 `"$CHECK" "$MAILBOX/$review" "$ORDER"`,不通过就拒派。
- **删掉 `--from-review`。** 有人传了,报:`--from-review was removed: declare the review in the order's front matter (review: <path relative to mailbox/>)`,退出 1。
- 更新文件头注释与用法说明。

提交信息:`scripts: orders declare review: in front matter; the gate only checks that every blocker is accounted for (D1 rework 3)`

### 第 4 步:测试

**现有 dispatch 用例里的工单夹具都要补上 `review:` 行**;删掉 `--source` 与 `--from-review` 相关的旧用例(换成下面的)。至少这些:

| 用例 | 期望 |
|---|---|
| 工单没有 `review:` 行 | 拒派;账本字节不变;LOGS 无新文件 |
| `review:` 写在正文里、不在 frontmatter | 同上 |
| 两行 `review:` | 拒派 |
| `review:` 还是模板占位符(直接从 `templates/work-order.zh.md` 读出那一行) | 拒派 |
| `review: none`、`review: None` | 照旧派单 |
| `review: to-hub/x-review.md`,文件在 `$MAILBOX` 下,返工单完整 | 派单 |
| 同上,返工单漏 B2 | 拒派,含 `missing B2` |
| `review:` 指向不存在的文件 | 拒派 |
| 传了 `--from-review` | 退出 1,信息含 `was removed` |
| 返工单 `修:` 后面分别是零宽空格、`—`、`?`、`……` | 1,`placeholder not filled` |
| 返工单 `修:<转写后的要求>。` | 1,`placeholder not filled` |
| **模板里每一个交代行占位符**(测试从四份模板里读出来,不要手抄)| 全部 1 |
| **已知局限,钉住**:`修:待补充`、`修:N/A`、`修:TODO: 转写` | **0**,用例名写明 `known limit` |
| `blockers: B1、B2`、`blockers: B1,B2`、`blockers: 无` | 按新规则通过 |
| `blockers: B1, B2,`(结尾多逗号) | 1,`unreadable` |
| 交代行缩进(`  - B1 → 修:x`) | 1,`missing B1` |
| `- B1 -> 修:x`(ASCII 箭头) | 1,`missing B1 (line N mentions B1` |
| 真实回归:返工单夹具改成新格式(frontmatter 带 `review:`) | 与原来结论一致 |

### 必须打的刀

| 刀 | 期望 |
|---|---|
| 缺 `review:` 行时当作 `none` | 「没有 review: 行」那条变红 |
| `review:` 路径按当前目录解析,不加 `$MAILBOX/` | 「文件在 $MAILBOX 下」那条变红 |
| 去掉「至少一个字母 / 数字 / 汉字」 | 零宽空格那条变红 |
| 去掉「包含模板字面占位」 | `<转写后的要求>。` 那条变红 |
| 清单不认 `、` | `B1、B2` 那条变红 |
| 去掉 S-f 提示 | ASCII 箭头那条变红 |
| 静默接受 `--from-review` | `was removed` 那条变红 |

**失败处理**:规则之间打架,或者真实回归过不去,照实写,别为了过而放宽。

## ⛔ 不许碰什么(越界即返工)

- 文档(`README*`、`PROTOCOL*`、`ACCEPTANCE*`、`SETUP*`、`BENCHMARK*`)不动 —— 另派一单。
- `templates/reply*.md` 不动。
- `scripts/accept.sh`、`scripts/statusline.sh` 不动。
- 不推送、不合并、不打 tag;测试不碰真账本和 `.shifts/`。
- 协调目录里的审查回信只读。
- 临时文件放进 `.scratch/`(已在 exclude 里),收尾删掉;删不掉就在回信里说。

## 怎么证明(交付时要附的实物)

- 第 1 步「先红」的原样输出
- 两个提交各自的 `--stat` 与完整 diff
- 修完后全量测试的原样输出
- 刀验表:每把刀 + 红/绿 + 确切失败信息 + 还原后 `git status --short` 为空
- 三值

## 回信

`to-hub/2026-09-19-d1-rework-3.md`,`status: NEW / from: builder`。最后一节必须是「我发现但没做的事」。
