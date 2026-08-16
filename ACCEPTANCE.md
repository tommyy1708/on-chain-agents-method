# Acceptance

**This is the expensive part.** The other rules exist to serve it.

*中文版:[ACCEPTANCE.zh.md](ACCEPTANCE.zh.md)*

---

## What counts as an artifact

| Counts | Does not |
|---|---|
| The diff itself | "I made the change" |
| Files and directory state on disk | "The file was created" |
| The **output** of a check, build or test run | "Tests pass" |
| A page you can open, a screen you can see | "The page works" |
| Real version-control state — branch, commit, clean tree | "It's committed" |

**The test: can a third party pull it up and look at it themselves?** If not, it is not an artifact.

---

## Three values must agree

Before accepting a change, line up three things: **branch, commit, and the contents of the diff.**

What the report says, what version control says, and what you can see — if those three disagree, stop and ask. Do not keep verifying downstream of a mismatch.

---

## ⭐ Mutation checks (knives)

**This is the core of the document.**

A passing test only proves *this code does not make it fail.* It does not prove **the test is guarding anything.**

So: **break the behaviour on purpose and see whether the test goes red.**

```
Not red = that guard is fake.
```

### How

1. Apply the mutation to **committed** code — not to a dirty working tree, or you risk swallowing someone else's work.
2. Run the **full** check suite, not just that one file. You need to know **how many went red, and which.**
3. Record the **exact failure message.** "It went red" is not a record. The message is.
4. Restore, and prove the restore is clean (an empty diff).

### Where to aim

**Aim at things that look correct and are not.** Aiming at obviously-broken code teaches you nothing.

| Weak knife | Strong knife |
|---|---|
| Delete the whole function | **Swap the order** of two actions |
| Set a constant to something absurd | Set it to **another plausible value** |
| Remove a block of config | Change an event name to **another valid but wrong one** |
| Make the code throw | Let it **run normally, with the behaviour quietly changed** |

> **A real lesson:** for the same hole, inserting the decoy **before** the real entry went red, while appending it **after** stayed green — because the assertion checked *presence*, never *only one*. **The shape of the knife changes the conclusion.**

### Who swings

**The reviewer swings, then the hub swings again — with different knives.**

Reviewers tend to test "is the thing there." The hub should cover "the thing is there, and it is wrong." **Two identical knives are one knife.**

---

## Fast lane or slow lane

- **Fast lane** (hub verification is enough): documentation, renames, dead-code removal — and any change where **zero behaviour change can be measured**.
- **Slow lane** (independent review required): anything that changes behaviour.
- **When unsure, slow lane.**

> "Zero behaviour change" must be **measured**, not felt: filter out non-product files and check that the diff is empty.

---

## Checklist before saying "ready to merge"

1. Three values agree
2. Automated checks **all green** — not "should be green"
3. Independent verdict is in, or the fast lane has been chosen **and the basis written down**
4. Mutation records complete, with exact failure messages
5. Is this stacked on another change? Should the branch be deleted after merge? **If stacked, warn against deleting**
6. What the human must do *after* the merge (re-sync a config, run a deploy step, place a verification call) — **stated once, in full**

---

## One discipline for the hub

**Before you repeat a reason someone below you wrote down, verify the reason itself.**

The criterion can be right while the reason is false. The human decides *while listening to that reason* — **repeat a false one and the approval rests on a false premise, even if the conclusion happens to be correct.**
