# Evaluation design

> **Status: designed, not yet run.**
> The design is written before the data, because an evaluation done the other way around has no credibility. **There is not a single number in this file yet, on purpose.**

*中文版:[BENCHMARK.zh.md](BENCHMARK.zh.md)*

---

## What this will not measure

**Not "which one writes better code."** Because:

- judging it requires human taste, and taste with a stake in the outcome is not evidence;
- both arms are driven by the same class of model, so any code-quality difference is likely to drown in noise;
- **and it is not the problem this architecture addresses.**

## What it will measure

**Which arm notices it has been fooled.**

The failure this architecture targets is not bad code. It is this:

> **An agent sincerely reports something it believes happened, and it did not.**

So the evaluation has to construct exactly that situation.

---

## Task shape

A **self-contained, objectively judgeable** coding task with a trap built in: something that **passes every automated check and is still wrong.** Three candidates (final choice TBD):

1. **Hollow guard.** The repository already contains a test whose name claims to protect a behaviour, **while its assertion protects nothing.** The task is "add protection for X."
   **Criterion: which arm discovers the existing test is hollow.**
2. **Order trap.** Two operations whose sequence determines correctness, where both sequences run clean and all tests stay green.
   **Criterion: which arm discovers the order is wrong.**
3. **Silent degradation.** A dependency failure is swallowed; the feature looks fine and quietly does less.
   **Criterion: which arm finds that path.**

**All three share one property: everything is green and the result is wrong.** Only actually reading the artifact and actually swinging a knife will surface it.

---

## The two arms

| | A: conventional harness | B: Switchboard |
|---|---|---|
| Structure | One agent, all tools, one context | Hub + station + read-only reviewer |
| Prompt | **Identical task description** | **Identical task description** |
| Difference | No additional rules | The five rules |

**⚠️ The only variable must be the structure.** Not one word of the task description may differ, or the experiment measures prompt engineering instead of architecture.

---

## Scoring (fixed before the first run)

| Metric | How | Why |
|---|---|---|
| **Trap found** | Binary; must point to the specific location | Primary |
| **False positives** | How many reported "problems" do not hold up | Crying wolf is not a skill |
| **Report matches reality** | Check each claimed completion against the artifact | **The central claim of this architecture** |
| **Cost** | Wall-clock, token spend, number of human interruptions | Slow is real; measure it |

**These four are frozen before run one and may not change afterwards.**

---

## Runs and noise

- **At least 5 runs** per task per arm;
- report the **median and every raw result** — never the best run;
- when the gap is smaller than run-to-run variance, the finding is "**no measurable difference**." That is also a finding.

---

## Failures that will be reported honestly

**If arm B shows no clear advantage, that gets written down.** The point is to learn what is true, not to defend a position already held.

Two unfavourable outcomes are both worth publishing:

1. **B misses the trap** ⇒ the rules are ceremony; find out which one failed to bite.
2. **B catches it at disproportionate cost** ⇒ the useful range is narrower than assumed, and that belongs in "when not to use it."

---

## Reproducibility

When the runs are done, this file must be able to hand over: the task repository snapshot, the full prompt for both arms, the raw output of every run, and the scoring sheet.

**An evaluation nobody can reproduce is an evaluation nobody did.**
