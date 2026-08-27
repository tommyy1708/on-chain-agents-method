# Protocol

This file is **written to be read by every station.** Put it (or a link to it) into each station's instructions file, so a fresh shift picks it up on start.

*中文版:[PROTOCOL.zh.md](PROTOCOL.zh.md)*

---

## Roles

| Role | Does | Hard boundary |
|---|---|---|
| **Human** | Decides; presses everything irreversible | Talks only to the hub |
| **Hub** | Writes orders, dispatches, accepts, keeps the ledger, reports to the human | **Does not write product code** (verification edits excepted — and they must be restored byte-identical) |
| **Station** | Does the work, produces artifacts | Touches only its own territory; never merges, never ships |
| **Review** | Reads artifacts, gives a verdict | **Zero write access; no direct channel to the station** |

**The topology is a hub and spokes.** Spokes do not connect to each other. Reviewer and author especially do not — that separation is the physical guarantee of review independence, not a matter of etiquette.

---

## Mailbox

```
mailbox/
  to-hub/          station → hub (replies, data, requests)
  to-<station>/    hub → a station (work orders)
  archive/         everything that has been handled
```

**One topic, one file**, named `YYYY-MM-DD-<slug>.md`.

### Message header

```markdown
---
status: NEW            # NEW / ACKED
from: hub              # hub / <station>
needs: <what this message asks of the recipient>
reply: to-hub/YYYY-MM-DD-<slug>.md
---
```

### State machine

`NEW` → recipient handles it → **appends the outcome to the bottom of the file** → sets `ACKED` → moves it to `archive/`.

**Do not skip the append.** The trace left at archive time is the only thing that can answer "why was this decided this way" three months later.

### Who may write to whom

- A station **writes only** to `to-hub/`, and **reads only** its own inbox.
- Stations **do not** post to each other. If another station is needed, write to the hub and let the hub transcribe.
- **Only the hub writes the ledger.** Stations may read it; they never edit it.

---

## Work orders

Use `templates/work-order.md`. A usable order answers four things:

1. **What** — the goal, and what counts as done.
2. **How** — the plan: order of operations, which tools, what to do when something fails. **Deciding "how" is the dispatcher's job. Do not outsource it to the person doing the work.**
3. **What must not be touched** — hard boundaries. Crossing one means redoing the work.
4. **How it will be proven** — which artifacts must come back.

> **One lesson:** a boundary written as a test holds better than a boundary written in an order. Orders go stale. Tests do not.

---

## Shifts

Each start is a **fresh, one-shot process**, running in that station's own directory, carrying one order.

- **No memory.** It works from the order plus what is on disk.
- **Narrow permissions — but confirm the flag is a boundary.** Grant the tools this order
  needs; a read-only job gets no write access. CLIs commonly have two flags that look alike:
  one **pre-approves** tools (so the agent is never stopped to ask), one decides **which tools
  exist**. Only the second restricts anything. Test yours once — hand a shift a single tool,
  ask it to use another — rather than assuming. Permissions are the second line of defence
  here. The first is that a shift is one order deep and a human presses merge.
- **One call, one shift.** Do not chain two in a single command — when one is killed, both die with nothing to show.
- **Run it in the background** so the driver's seat stays free. Different stations run in parallel; the same station queues.

### Four things the launch prompt must state

1. The path to the order, and that it is to be followed strictly.
2. A summary of this shift's hard guardrails (no deploy, no production, no real external calls, open a PR but do not merge, …).
3. Where the reply goes, and in what shape.
4. **How to sign off.** The last thing a shift does, after the reply is on disk, is emit one
   line in a fixed shape:

   ```
   SHIFT-END <station> <order-slug> <done|failed|stuck> · <one sentence> · reply <path>
   ```

   **A shift that stops early emits it too** — `stuck`, plus where it stopped. Silence is the
   worst outcome: an agent that dies quietly looks exactly like an agent still working, and
   the hub finds out an hour later. One line costs nothing and removes that hour.

   Where the line goes depends on your CLI. If it can message another session, send it to the
   hub and the hub hears it immediately. If it cannot, printing it is enough — it becomes the
   last line of the shift log, so `tail -1 <log>` answers "how did that end?" without reading
   the log at all. **The reply file is still the record.** This line is a doorbell, not a
   deliverable: it is allowed to be lost, the reply is not.

---

## The ledger

One JSON file, **written only by the hub**, holding three things:

- whether each station is **idle or running**, on what, since when;
- items **waiting on a human decision**;
- **the trace**: every dispatch, every acceptance, every decision — **with the reasoning as it stood at the time.**

**Dispatching and recording must be the same action.** Miss once and the status display is lying.

**And give the ledger something that can contradict it.** The rule above is discipline, and
discipline is exactly what fails at 2am. So record the shift's **process id** at dispatch, and
have the status display check it: a station marked `running` whose process is gone is not a
station running — it is a ledger that was never closed out. One `kill -0` per running station,
no dependency on any particular CLI, and the display stops being able to lie in the one
direction that matters. (If your CLI can also enumerate its own sessions, that is a stronger
check still — it catches the reverse case, a shift running that nobody wrote down.)

This is the same principle the rest of the model runs on: **never let the only account of the
work be the account written by whoever did it.** The ledger is the hub's own report on itself,
so it gets a witness too.

> Shape: `ledger.example.json`. `scripts/statusline.sh` reads it, checks each running pid, and
> prints who is busy — flagging any station whose process has vanished.

---

## Reporting to the human

**Fixed shape, fixed order** — the order exists so the reader can decide within two lines whether to keep reading.

```
You need to      : <nothing | decide | merge | go do X somewhere>
Bottom line      : <one sentence>

What this is     : <the thing itself>
Why it matters   : <what happens if we don't — consequences, not theory>
How it was checked: <ran it myself? independently verified? or just read the report?>
Blocked on       : <the human / a station / nobody>
```

**Three to five lines by default.** Detail goes into files; the chat gets one pointer. **Never drop "how it was checked"** — ran it myself, independently verified, and read the report are three very different levels of confidence.

**One task per report.** Three things means three blocks, separated.
