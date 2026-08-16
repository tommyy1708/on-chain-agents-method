# 上手

怎么把这套东西用在你自己的代码库上。到发出第一单,大约三十分钟。

*English (primary): [SETUP.md](SETUP.md)*

---

## 需要什么

- **bash** 和 **python3** —— macOS 与 Linux 自带
- **git** —— 实物要能被别人调出来看,这正是 git 的用处
- **一个能一次性、非交互运行的 agent CLI**:提示词作为参数传入,并且能限制它可以使用哪些工具

最后一条是唯一的硬要求。一个具体例子,也是这些脚本对着写的那个:

```bash
claude -p "<prompt>" --allowedTools "Read,Grep,Write,Bash(git:*)"
```

任何长这个形状的 CLI 都能用。**如果你的工具不能限制权限,其余内容照样成立,只有第 4 条规矩用不上。**

---

## 目录怎么摆

三种目录。**把它们分开,就是这套配置的全部。**

```
~/work/
  my-project/              你的代码库 —— 事实源
  stations/
    backend/               my-project 的一份工作副本
    frontend/              另一份工作副本
    review/                另一份工作副本 —— 靠纪律保持只读
  coordination/            这个仓:mailbox/ · ledger.json · scripts/
```

关于这张图的三条规矩,每一条都是撞出来的:

1. **每个工位一份自己的工作副本。** 两个班次挤在一个目录里一定打架 —— 一个在切分支,另一个正改到一半,然后你要花一下午分辨那些改动是谁的。
2. **协调目录不属于任何工位。** 信箱和账本如果落在某个工位的地盘里,**那个工位就能改自己的成绩单**。它不会出于恶意这么做,它会出于"帮忙"这么做。
3. **审查工位也需要一份工作副本。** 它要跑检查,而且必须**不碰原件** —— 用一份临时副本打刀,是"只读"这件事既成立、又还能真正动手的唯一办法。

**用 worktree 还是各自克隆?** 如果是同一个仓,先用 worktree:共用一个 `.git`,几乎没有成本,而且分支在各工位之间互相可见。当各工位本来就分属不同仓库,或者你希望隔离是物理性的,再用独立克隆。

---

## 第 1 步 —— 取文件

```bash
mkdir -p ~/work && cd ~/work
git clone https://github.com/tommyy1708/on-chain-agents-method.git coordination
cd coordination
cp ledger.example.json ledger.json     # ledger.json 已被 gitignore:它是你的,不是这个仓的
```

## 第 2 步 —— 建工位

```bash
mkdir -p ~/work/stations

# 同一个仓的 worktree
git -C ~/work/my-project worktree add ~/work/stations/backend  -b station/backend
git -C ~/work/my-project worktree add ~/work/stations/frontend -b station/frontend
git -C ~/work/my-project worktree add ~/work/stations/review   -b station/review

# 或者各自克隆
# git clone <url> ~/work/stations/backend
```

然后让名字在三处对齐 —— 目录、收件箱、账本:

```bash
cd ~/work/coordination
mv mailbox/to-station-a mailbox/to-backend
mv mailbox/to-station-b mailbox/to-frontend
# 再改 ledger.json,让 agents 里是 backend / frontend / review
```

## 第 3 步 —— 指向你的 agent

```bash
export AGENT_CMD="claude -p"              # 换成你自己的 CLI
export STATIONS_DIR="$HOME/work/stations"
```

**先空跑一次。** 把 `AGENT_CMD` 设成 `echo`,脚本就只打印提示词,不真的跑 agent:

```bash
AGENT_CMD="echo" ./scripts/dispatch.sh backend mailbox/to-backend/2026-01-05-thing.md --fg
```

你会看到工位**本来会收到的那份提示词**。**把它读一遍。** 提示词不对,后面没有一件事会是对的。

## 第 4 步 —— 给每个工位一份常驻说明

每个工位目录里要有一份它的 agent 开工时会读的说明文件 —— Claude Code 是工作副本根目录下的 `CLAUDE.md`。很短:

```markdown
# 你是 backend 工位

## 你的地盘
- `src/server/`、`db/`,以及覆盖它们的测试

## 绝不
- 别人的地盘。需要那边改动,写信给枢纽。
- 合并、上线、发布、强制推送。这些是人按的。
- 协调目录。你读自己的收件箱,绝不改账本。

## 这里怎么做事
<把 PROTOCOL.zh.md 贴进来或链过去>
```

**地盘要写成路径,不要写成岗位描述。** 「后端」可以有各种解读,`src/server/` 不能。

## 第 5 步 —— 完整跑一单

```bash
cd ~/work/coordination
cp templates/work-order.zh.md mailbox/to-backend/2026-01-05-add-retry.md
$EDITOR mailbox/to-backend/2026-01-05-add-retry.md      # 四节都要填

./scripts/dispatch.sh backend mailbox/to-backend/2026-01-05-add-retry.md \
    --tools "Read,Grep,Write,Edit,Bash(git:*),Bash(npm test:*)"

./scripts/statusline.sh          # backend:… · inbox 0 · awaiting decision 0
```

回信落进 `mailbox/to-hub/` 之后:

1. **读实物,不是读回信。** 自己打开那份改动,自己跑一遍检查。
2. **打一把工位没打的刀。** 故意把行为改坏;**什么都不红,那道保护就是空的。**(见 [ACCEPTANCE.zh.md](ACCEPTANCE.zh.md))
3. 然后,才:

```bash
./scripts/accept.sh backend --note "自己跑了全量 812→815 全绿;打了一把它没打的刀(把两处写入调换顺序),红了,报 'retry re-sends on crash';还原干净。"
```

把处理结果追加到回信文末,改成 `status: ACKED`,移进 `mailbox/archive/`。

**这一圈就是产品本身。** 这个仓里其余所有东西,都是为了让这一圈保持诚实。

## 第 6 步 —— 加审查工位,但不是今天

先用两条规矩跑一周:**实物验收** 和 **状态落盘**。它们能解决大部分问题,而且不花钱。

等你撞上第二种失败 —— **某个东西错了一阵子而没人发现** —— 再加审查工位。那一刻你自己会知道,而且审查这件事到那时才讲得通,现在还讲不通。

---

## 别这么干

- **别把信箱或账本放进工位的工作副本里。** 见布局第 2 条。
- **别在一个工位目录里同时跑两个班次。** `dispatch.sh` 会拒绝;**别绕过它。**
- **别让工位写账本。** 读可以。一旦能写,账本就从记录变成了故事。
- **别省 `--note`。** 脚本不让你省,这正是它存在的意义。
- **别"就这一次"给审查方写权限。** 你给的那一次,正好就是它把问题顺手修掉、而不是报出来的那一次 —— 于是没人知道那道保护本来是空的。

---

## 出问题时

**`station 'x' is 'running', not idle`**
上一个班次没验收过。去 `.shifts/` 看它的日志,然后跑 `accept.sh`。班次要是死了,就在 note 里照实写 —— 「14:20 被杀,什么都没落盘,重派」是一条完全合格的账本记录。

**dispatch 只打印了提示词就退出了**
`AGENT_CMD` 还是 `echo`。那是空跑。

**工位跑到别人的地盘上去了**
说明文件写得太含糊。**把地盘改写成路径。** 这几乎从来不是 agent 不听话,是那条边界根本没法执行。

**回信说全都通过了,其实没有**
**这正是这个仓存在的全部前提。** 去读 [ACCEPTANCE.zh.md](ACCEPTANCE.zh.md),然后打一把刀。
