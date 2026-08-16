# Setup

How to run this on your own codebase. About thirty minutes to the first order.

*中文版:[SETUP.zh.md](SETUP.zh.md)*

---

## What you need

- **bash** and **python3** — both already on macOS and Linux
- **git** — the artifacts have to be inspectable, and that is what git is for
- **an agent CLI** that can run **one-shot and non-interactive**, takes the prompt as an argument, and can restrict which tools it may use

That last one is the only real requirement. A concrete example, and the one these scripts were written against:

```bash
claude -p "<prompt>" --allowedTools "Read,Grep,Write,Bash(git:*)"
```

Any CLI with that shape works. If yours cannot restrict tools, everything here still applies except rule 4.

---

## The layout

Three kinds of directory. **Keeping them separate is the setup.**

```
~/work/
  my-project/              your codebase — the source of truth
  stations/
    backend/               a working copy of my-project
    frontend/              another working copy
    review/                another working copy — read-only by discipline
  coordination/            this repository: mailbox/ · ledger.json · scripts/
```

Three rules about that picture, each one learned the hard way:

1. **Every station gets its own working copy.** Two shifts in one directory will fight — one checks out a branch while the other is mid-edit, and you will spend an afternoon working out whose changes those were.
2. **The coordination directory belongs to no station.** If the mailbox and the ledger sit inside a station's territory, that station can edit its own report card. It will not do so maliciously. It will do so helpfully.
3. **The reviewer needs a working copy too.** It has to run checks, and it has to do that **without touching the original** — a scratch copy is how "read-only" stays true while still being able to swing a knife.

**Worktrees or separate clones?** For one repository, start with worktrees: they share a single `.git`, cost almost nothing, and branches are visible across stations. Use separate clones when the stations are separate repositories anyway, or when you want the isolation to be physical.

---

## Step 1 — get the files

```bash
mkdir -p ~/work && cd ~/work
git clone https://github.com/tommyy1708/on-chain-agents-method.git coordination
cd coordination
cp ledger.example.json ledger.json     # ledger.json is gitignored; it is yours, not the repo's
```

## Step 2 — create your stations

```bash
mkdir -p ~/work/stations

# worktrees of one repository
git -C ~/work/my-project worktree add ~/work/stations/backend  -b station/backend
git -C ~/work/my-project worktree add ~/work/stations/frontend -b station/frontend
git -C ~/work/my-project worktree add ~/work/stations/review   -b station/review

# or separate clones
# git clone <url> ~/work/stations/backend
```

Then make the names line up in three places — the directory, the inbox, and the ledger:

```bash
cd ~/work/coordination
mv mailbox/to-station-a mailbox/to-backend
mv mailbox/to-station-b mailbox/to-frontend
# and edit ledger.json so agents has: backend, frontend, review
```

## Step 3 — point it at your agent

```bash
export AGENT_CMD="claude -p"              # substitute your own CLI
export STATIONS_DIR="$HOME/work/stations"
```

**Do a dry run first.** Set `AGENT_CMD` to `echo` and the script prints the prompt instead of running an agent:

```bash
AGENT_CMD="echo" ./scripts/dispatch.sh backend mailbox/to-backend/2026-01-05-thing.md --fg
```

You will see exactly what the station would have received. **Read it.** If the prompt is wrong, nothing downstream can be right.

## Step 4 — give each station its standing instructions

Every station directory needs an instructions file its agent reads on start — for Claude Code that is `CLAUDE.md` at the root of the working copy. It is short:

```markdown
# You are the backend station

## Your territory
- `src/server/`, `db/`, the tests that cover them

## Never
- Another station's territory. If you need a change there, write to the hub.
- Merge, deploy, publish, force push. A human presses those.
- The coordination directory. You read your inbox; you never edit the ledger.

## How we work here
<paste or link PROTOCOL.md>
```

**Write the territory as paths, not as a job description.** "Backend" is open to interpretation; `src/server/` is not.

## Step 5 — run one order, end to end

```bash
cd ~/work/coordination
cp templates/work-order.md mailbox/to-backend/2026-01-05-add-retry.md
$EDITOR mailbox/to-backend/2026-01-05-add-retry.md      # fill in all four sections

./scripts/dispatch.sh backend mailbox/to-backend/2026-01-05-add-retry.md \
    --tools "Read,Grep,Write,Edit,Bash(git:*),Bash(npm test:*)"

./scripts/statusline.sh          # backend:… · inbox 0 · awaiting decision 0
```

When the reply lands in `mailbox/to-hub/`:

1. **Read the artifact, not the reply.** Open the diff yourself. Run the checks yourself.
2. **Swing one knife the station did not.** Break the behaviour on purpose; if nothing goes red, the guard is hollow. ([ACCEPTANCE.md](ACCEPTANCE.md))
3. Then, and only then:

```bash
./scripts/accept.sh backend --note "ran the suite myself 812→815 green; swung a knife it \
had not (swapped the two writes), red with 'retry re-sends on crash'; restore clean."
```

Append your outcome to the bottom of the reply file, set `status: ACKED`, move it to `mailbox/archive/`.

**That whole loop is the product.** Everything else in this repository exists to keep it honest.

## Step 6 — add the reviewer, but not today

Run with two rules for a week: **artifact acceptance** and **state on disk**. They solve most of it, and they cost nothing.

Add the review station once you have hit the second failure — the one where something was wrong for a while and nobody noticed. You will know it when it happens, and the reviewer will make sense then in a way it does not now.

---

## Don't

- **Don't put the mailbox or the ledger inside a station's working copy.** See layout rule 2.
- **Don't run two shifts in one station directory.** `dispatch.sh` refuses; do not work around it.
- **Don't let a station write the ledger.** Reading is fine. Writing makes the ledger a story rather than a record.
- **Don't skip the `--note`.** The script will not let you, and that is the point.
- **Don't give the reviewer write access "just this once."** The one time you do is the time it fixes the thing instead of reporting it, and nobody ever learns the guard was hollow.

---

## Troubleshooting

**`station 'x' is 'running', not idle`**
A previous shift was never accepted. Check its log under `.shifts/`, then run `accept.sh`. If the shift died, say so in the note — "killed at 14:20, nothing landed, re-dispatching" is a perfectly good ledger entry.

**dispatch prints the prompt and exits**
`AGENT_CMD` is still `echo`. That is the dry run.

**The station did something outside its territory**
The instructions file is too vague. Rewrite the territory as paths. This is almost never the agent being disobedient; it is the boundary being unwriteable.

**The reply says everything passed, and it did not**
That is the entire premise of this repository. Go read [ACCEPTANCE.md](ACCEPTANCE.md) and swing a knife.
